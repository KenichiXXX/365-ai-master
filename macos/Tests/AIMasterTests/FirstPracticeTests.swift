import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class FirstPracticeTests: XCTestCase {
    private func result(_ status: String, count: Int = 0) throws -> EngineResult {
        try EngineRunner.decode(Data("""
        {"schema":3,"coverage":{"codex":{"adapter_version":"1","format":"test",
        "status":"\(status)","valid_usage_count":\(count),"malformed_count":0,"skipped_count":0,"signals":{}}}}
        """.utf8), status: 0)
    }

    func testFourBranchesAndPracticeWithEveryOptionalChoiceDeclined() async throws {
        for (status, count, branch) in [("ok", 1, FirstPracticeBranch.usableLogs),
            ("no_logs", 0, .noLogs), ("unsupported", 0, .unsupported), ("permission_denied", 0, .permissionDenied)] {
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            defaults.set([String](), forKey: "enabledTools")
            let snapshot = try result(status, count: count)
            let store = SnapshotStore(defaults: defaults, load: { _, _ in snapshot })
            store.publicDownloads = false
            store.notificationsEnabled = false
            XCTAssertFalse(store.shareAnonymousScore)
            await store.refresh()?.value
            XCTAssertEqual(store.firstPracticeBranch, branch)
            store.chooseObstacle(.noProject)
            XCTAssertTrue(store.firstPracticePrompt(locale: "en").contains("Do not run commands"))
            store.recordFirstPractice(.copied)
            XCTAssertEqual(store.practiceStatus, .copied)
            store.recordFirstPractice(.selfReported)
            XCTAssertEqual(store.practiceStatus, .selfReported)
            store.chooseObstacle(.skipped)
            XCTAssertEqual(store.practiceStatus, .ready)
            XCTAssertNil(store.snapshot?.village)
            XCTAssertFalse(store.isPro)
        }
    }

    func testOnboardingResumesAndPreservesExplicitPreferences() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(["codex"], forKey: "enabledTools")
        defaults.set(false, forKey: "publicDownloads")
        defaults.set(false, forKey: "notificationsEnabled")
        let store = SnapshotStore(defaults: defaults)
        store.advanceOnboarding()
        store.chooseObstacle(.noProject)
        store.recordFirstPractice(.copied)
        let resumed = SnapshotStore(defaults: defaults)
        XCTAssertEqual(resumed.onboardingStep, .practice)
        XCTAssertEqual(resumed.obstacle, .noProject)
        XCTAssertEqual(resumed.practiceStatus, .copied)
        XCTAssertEqual(resumed.enabledTools, ["codex"])
        XCTAssertEqual(resumed.publicDownloads, false)
        XCTAssertFalse(resumed.notificationsEnabled)
        resumed.dismissOnboarding()
        XCTAssertEqual(SnapshotStore(defaults: defaults).onboardingStep, .done)
    }

    func testNoPublicRequestBeforeChoiceOrAfterDecline() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var calls = 0
        let store = SnapshotStore(defaults: defaults)
        store.downloadContent = { calls += 1; return false }
        await store.refreshContent().value
        XCTAssertEqual(calls, 0)
        store.publicDownloads = false
        await store.refreshContent().value
        XCTAssertEqual(calls, 0)
        store.publicDownloads = true
        await store.refreshContent().value
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(store.shareAnonymousScore)
        XCTAssertFalse(store.notificationsEnabled)
    }

    func testMixedCoveragePrefersUsableEvidenceAndPersistsBranch() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let good = try result("partial", count: 1)
        let store = SnapshotStore(defaults: defaults, load: { _, _ in good })
        await store.refresh()?.value
        XCTAssertEqual(store.firstPracticeBranch, .usableLogs)
        XCTAssertEqual(SnapshotStore(defaults: defaults).firstPracticeBranch, .usableLogs)
        XCTAssertEqual(SnapshotStore(defaults: defaults).publicDownloads, nil)
    }
    func testBundledPromptsAndEveryBranchRenderWithoutNetwork() async throws {
        for locale in ["zh", "en"] {
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            let store = SnapshotStore(defaults: defaults)
            func render(_ name: String) throws {
                let renderer = ImageRenderer(content: FirstPracticeView(store: store, locale: locale)
                    .padding(16).frame(width: 440)
                    .environment(\.locale, Locale(identifier: locale))
                    .background(Color(nsColor: .windowBackgroundColor)))
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertEqual(image.size.width, 440)
                XCTAssertLessThan(image.size.height, 660)
                if let out = ProcessInfo.processInfo.environment["RENDER_OUT"] {
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: URL(fileURLWithPath: out + "-onboarding-" + name + "-" + locale + ".png"))
                }
            }
            try render("sources")
            store.advanceOnboarding()
            try render("obstacle")
            store.chooseObstacle(.skipped)
            XCTAssertTrue(store.firstPracticePrompt(locale: locale).contains(locale == "zh" ? "不要修改文件" : "Do not modify files"))
            for status in ["ok", "no_logs", "unsupported", "permission_denied"] {
                let snapshot = try result(status, count: status == "ok" ? 1 : 0)
                store.load = { _, _ in snapshot }
                await store.refresh()?.value
                try render(status)
            }
            store.chooseObstacle(.noProject)
            XCTAssertTrue(store.firstPracticePrompt(locale: locale).contains(locale == "zh" ? "不要执行命令" : "Do not run commands"))
            store.recordFirstPractice(.selfReported)
            try render("planning")
        }
    }

    func testOwnedSubprocessActuallyTerminatesAndRetryWorks() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../").standardizedFileURL
        let directory = root.appendingPathComponent(".pytest_cache/process-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("ready")
        let python = root.appendingPathComponent(".venv/bin/python")
        let scan = EngineScan()
        let child = Task.detached {
            try scan.run(executable: python, arguments: ["-c",
                "import pathlib,signal,sys; pathlib.Path(sys.argv[1]).touch(); signal.pause()", marker.path])
        }
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: marker.path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        scan.cancel()
        do { _ = try await child.value; XCTFail("Cancelled scan must discard its output") }
        catch { XCTAssertTrue(error is CancellationError) }
        let retry = EngineScan()
        let (data, status) = try await Task.detached {
            try retry.run(executable: python, arguments: ["-c", "print('ready')"])
        }.value
        XCTAssertEqual(status, 0)
        XCTAssertEqual(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), "ready")
    }

}

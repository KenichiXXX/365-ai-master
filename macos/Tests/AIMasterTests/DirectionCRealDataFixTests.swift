import XCTest
import SwiftUI
import Vision
@testable import AIMaster

@MainActor
extension RenderPreviewTests {
    private func fixRender<V: View>(_ view: V, scheme: ColorScheme) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "zh")))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        bitmap.size = hosting.bounds.size
        return bitmap
    }

    private func fixText(_ bitmap: NSBitmapImageRep) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.usesCPUOnly = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.minimumTextHeight = 0.005
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return request.results ?? []
    }

    private func assertSolidButton(_ bitmap: NSBitmapImageRep, title: String, scheme: ColorScheme,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let observations = try fixText(bitmap)
        let label = try XCTUnwrap(observations.first {
            $0.topCandidates(1).first?.string.replacingOccurrences(of: " ", with: "").contains(title) == true
        }, title, file: file, line: line)
        let box = label.boundingBox
        var textPixels = 0
        let expectedText = scheme == .light ? [25.0 / 255, 21.0 / 255, 15.0 / 255] : [18.0 / 255, 22.0 / 255, 31.0 / 255]
        for y in Int((1 - box.maxY) * Double(bitmap.pixelsHigh))..<Int((1 - box.minY) * Double(bitmap.pixelsHigh)) {
            for x in Int(box.minX * Double(bitmap.pixelsWide))..<Int(box.maxX * Double(bitmap.pixelsWide)) {
                if let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    let distance = zip([pixel.redComponent, pixel.greenComponent, pixel.blueComponent], expectedText)
                        .map { abs($0 - $1) }.max() ?? 1
                    if distance < 0.06 { textPixels += 1 }
                }
            }
        }
        XCTAssertGreaterThan(textPixels, 5, "Actionable primary text must use onAccent (allowing glyph antialiasing)", file: file, line: line)
        let x = Int(box.midX * Double(bitmap.pixelsWide))
        // Sample the fill just below the glyphs, inside the button's vertical padding.
        let y = Int((1 - box.minY) * Double(bitmap.pixelsHigh)) + 4
        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        let expected = scheme == .light ? [217.0, 161.0, 46.0] : [240.0, 190.0, 90.0]
        for (actual, byte) in zip([color.redComponent, color.greenComponent, color.blueComponent], expected) {
            XCTAssertEqual(actual, byte / 255, accuracy: 0.015, title, file: file, line: line)
        }
    }

    func testDirectionCActionableButtonsDuringRefreshAndNamedPicks() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        object["locale"] = "zh"
        object["dimensions"] = [["key": "routing", "label": "模型路由", "score": 35]]
        object["rankings"] = ["origin": "bundled", "skill": [], "agent": [[
            "name": "stanfordnlp/dspy", "url": "https://github.com/stanfordnlp/dspy",
            "tagline": "把提示词写成可优化的程序", "task_category": "agent"]]]
        var game: [String: Any] = ["xp": 130, "level": 3, "level_xp": 30, "next_level_xp": 150, "level_title": "Novice", "shields": 0, "streak": 0, "best_streak": 0, "month": "2026-10", "first_weekday": 3, "calendar": [], "weekly_badges": []]
        game["weekly"] = ["week": "2026-W43", "kind": "checkins", "title": "打卡 5 天", "have": 0, "need": 5, "earned": false]
        game["today"] = ["checkin": false, "card_read": false, "practice": false, "completed": 0]
        object["training_game"] = game
        let result = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0)
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
        await store.refresh()?.value
        let started = expectation(description: "refresh started")
        let gate = DispatchSemaphore(value: 0)
        store.load = { _, _ in started.fulfill(); gate.wait(); return result }
        let refreshing = try XCTUnwrap(store.refresh())
        await fulfillment(of: [started], timeout: 3)
        defer { gate.signal() }
        for scheme in [ColorScheme.light, .dark] {
            let picks = try fixRender(TodaySkillTab(snapshot: result.snapshot, store: store).frame(width: 400), scheme: scheme)
            try assertSolidButton(picks, title: "复制试一下", scheme: scheme)
            let text = try fixText(picks).compactMap { $0.topCandidates(1).first?.string }.joined()
            XCTAssertTrue(text.contains("dspy"), text)
            let training = try fixRender(TrainingGameView(game: XCTUnwrap(result.snapshot.trainingGame), store: store, zh: true)
                .frame(width: 400).bauhausTheme(), scheme: scheme)
            try assertSolidButton(training, title: "打卡+5XP", scheme: scheme)
        }
        gate.signal()
        await refreshing.value
    }

    func testDirectionCActionsQueueBehindRefresh() async throws {
        let result = try EngineRunner.decode(Data(#"{"schema":3,"locale":"zh"}"#.utf8), status: 0)
        for practice in [false, true] {
            let started = expectation(description: "refresh started")
            let gate = DispatchSemaphore(value: 0)
            let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
            store.load = { _, _ in started.fulfill(); gate.wait(); return result }
            let refresh = try XCTUnwrap(store.refresh())
            await fulfillment(of: [started], timeout: 3)
            store.load = { _, _ in result }
            let executed = expectation(description: "action executed")
            store.actionCommand = { args in
                XCTAssertEqual(args, practice ? ["practice", "plan", "copy"] : ["checkin"])
                executed.fulfill()
                return true
            }
            let action = practice ? store.practice(id: "plan", operation: "copy") : store.checkIn()
            XCTAssertNotNil(action, "A refresh must not drop an actionable command")
            gate.signal()
            await refresh.value
            await action?.value
            await fulfillment(of: [executed], timeout: 3)
        }
    }

    func testDirectionCCompletedActionsDoNotDisableButtonsDuringFollowupRefresh() async throws {
        let result = try EngineRunner.decode(Data(#"{"schema":3,"locale":"zh"}"#.utf8), status: 0)
        for practice in [false, true] {
            let started = expectation(description: "post-action refresh started")
            let gate = DispatchSemaphore(value: 0)
            let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
            store.actionCommand = { _ in true }
            store.load = { _, _ in started.fulfill(); gate.wait(); return result }
            let action = practice ? store.practice(id: "plan", operation: "copy") : store.checkIn()
            await fulfillment(of: [started], timeout: 3)
            XCTAssertTrue(store.isRefreshing)
            XCTAssertFalse(store.isPerformingAction, "The command finished; its background read must not disable buttons")
            gate.signal()
            await action?.value
        }
    }

    func testRenderDirectionCRealDataFixes() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PHASE7_SNAPSHOT_DIR"],
              let output = ProcessInfo.processInfo.environment["PHASE7_RENDER_OUT"] else {
            throw XCTSkip("set PHASE7_SNAPSHOT_DIR and PHASE7_RENDER_OUT")
        }
        let result = try EngineRunner.decode(Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("zh.json")), status: 0)
        XCTAssertGreaterThan(result.snapshot.usageSummary?.tokens7d ?? 0, 0)
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
        store.actionCommand = { _ in true }
        await store.refresh()?.value
        store.dismissOnboarding()
        for scheme in [ColorScheme.light, .dark] {
            for tab in 0...2 {
                let defaults = UserDefaults(suiteName: UUID().uuidString)!
                defaults.set(tab, forKey: "selectedTab")
                let bitmap = try fixRender(PopoverView(store: store).defaultAppStorage(defaults), scheme: scheme)
                XCTAssertEqual(bitmap.size, NSSize(width: 440, height: 720))
                if tab == 0 {
                    let tokens = try XCTUnwrap(try fixText(bitmap).first { $0.topCandidates(1).first?.string.contains("tokens") == true })
                    XCTAssertGreaterThan(tokens.boundingBox.minY * 720, 65, "Usage must be fully above the footer")
                }
                if tab == 1 { try assertSolidButton(bitmap, title: "复制试一下", scheme: scheme) }
                if tab == 2, result.snapshot.trainingGame?.today.checkin == false {
                    try assertSolidButton(bitmap, title: "打卡+5XP", scheme: scheme)
                }
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: output + "-task62-zh-\(tab)-\(scheme).png"))
            }
        }
    }
}

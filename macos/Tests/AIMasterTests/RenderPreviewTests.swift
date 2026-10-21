import XCTest
import SwiftUI
@testable import AIMaster

// Opt-in local preview; real usage and generated PNGs must never be committed.
@MainActor
final class RenderPreviewTests: XCTestCase {
    func testRenderPopoverSections() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        let store = SnapshotStore(defaults: UserDefaults(suiteName: "render-preview")!) { locale, tools in
            let process = Process()
            process.executableURL = try XCTUnwrap(EngineRunner.engineURL())
            // Use bundled content and isolated progress; optionally a synthetic home.
            let content = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../../content/daily.json").standardizedFileURL
            process.arguments = EngineRunner.snapshotArguments(locale: locale, tools: tools, content: content)
                + ["--state-dir", URL(fileURLWithPath: out).deletingLastPathComponent()
                    .appendingPathComponent("render-state").path]
            if let home = ProcessInfo.processInfo.environment["AIMASTER_PREVIEW_HOME"] {
                process.arguments! += ["--home", URL(fileURLWithPath: home).standardizedFileURL.path, "--state-dir", out + ".state"]
            }
            let pipe = Pipe(); process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return try EngineRunner.decode(data, status: process.terminationStatus)
        }
        await store.refresh()?.value
        let snap = try XCTUnwrap(store.snapshot, store.lastError ?? "no snapshot")
        XCTAssertEqual(snap.schema, 3, "Rebuild dist/365engine before rendering")
        let views: [(String, AnyView)] = [
            ("checkup", AnyView(CheckupTab(snapshot: snap, store: store))),
            ("today", AnyView(TodaySkillTab(snapshot: snap, store: store))),
            ("training", AnyView(TrainingTab(snapshot: snap, store: store)))
        ]
        for (name, tab) in views {
            let view = tab.padding(16).frame(width: 440)
                .background(Color(nsColor: .windowBackgroundColor))
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let img = try XCTUnwrap(renderer.nsImage)
            if name == "training" {
                XCTAssertEqual(img.size.width, 440)
                XCTAssertLessThanOrEqual(img.size.height, 1100)
                XCTAssertEqual(snap.book?.groups?.map(\.total), [8, 10, 6])
                print("Training preview: \(img.size.width) x \(img.size.height) pt")
            }
            let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(img.tiffRepresentation)))
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: out + "-" + name + ".png"))
        }
        let popover = ImageRenderer(content: PopoverView(store: store)); popover.scale = 2
        let image = try XCTUnwrap(popover.nsImage)
        XCTAssertEqual(image.size.width, 440)
        XCTAssertLessThanOrEqual(image.size.height, 720)
    }
    func testRenderActionCoverageStates() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        let root = URL(fileURLWithPath: out + "-fixtures-" + UUID().uuidString).standardizedFileURL
        let timestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        for state in ["empty", "partial", "evaluable"] {
            let home = root.appendingPathComponent(state)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            if state != "empty" {
                let relative = state == "partial" ? ".claude/projects/demo/a.jsonl" : ".codex/sessions/a.jsonl"
                let log = home.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
                let lines = state == "partial" ? [
                    #"{"type":"user","uuid":"u1","timestamp":"TIME","message":{"content":"synthetic task"}}"#,
                    #"{"type":"assistant","timestamp":"TIME","message":{"id":"a1","model":"claude-sonnet-5","content":[],"usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":400}}}"#
                ] : [
                    #"{"type":"turn_context","timestamp":"TIME","payload":{"model":"gpt-6.1-sol"}}"#,
                    #"{"type":"event_msg","timestamp":"TIME","payload":{"type":"task_started"}}"#,
                    #"{"type":"token_usage_record","timestamp":"TIME","payload":{"response_id":"r1","turn_id":"t1","usage":{"input_tokens":500,"cached_input_tokens":400,"output_tokens":20}}}"#
                ]
                try (lines.joined(separator: "\n").replacingOccurrences(of: "TIME", with: timestamp) + "\n")
                    .write(to: log, atomically: true, encoding: .utf8)
            }
            for locale in ["zh", "en"] {
                let isolatedState = root.appendingPathComponent("state-" + state + "-" + locale)
                let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!) { _, _ in
                    let process = Process()
                    process.executableURL = try XCTUnwrap(EngineRunner.engineURL())
                    process.arguments = ["snapshot", "--json", "--locale", locale,
                                         "--home", home.path, "--state-dir", isolatedState.path]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    return try EngineRunner.decode(data, status: process.terminationStatus)
                }
                store.dismissOnboarding()
                await store.refresh()?.value
                let snapshot = try XCTUnwrap(store.snapshot, store.lastError ?? "no snapshot")
                XCTAssertEqual(snapshot.overall?.availability,
                               ["empty": "unavailable", "partial": "partial", "evaluable": "available"][state])
                XCTAssertEqual(snapshot.hasEvaluableScores, state == "evaluable")
                let renderer = ImageRenderer(content: CheckupTab(snapshot: snapshot, store: store)
                    .padding(16).frame(width: 440).environment(\.locale, Locale(identifier: locale))
                    .background(Color(nsColor: .windowBackgroundColor)))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertEqual(image.size.width, 440)
                let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: out + "-" + state + "-" + locale + ".png"))
                if state == "empty", locale == "en" {
                    let id = try XCTUnwrap(snapshot.todayTip?.actionId)
                    XCTAssertTrue(try EngineRunner.actionCommand(["action-feedback", id, "not_suitable",
                        "--reason", "no_project", "--state-dir", isolatedState.path]))
                    await store.refresh()?.value
                    let alternative = try XCTUnwrap(store.snapshot?.todayTip?.actionId)
                    XCTAssertNotEqual(alternative, id)
                    XCTAssertEqual(store.snapshot?.todayTip?.source.kind, "pool")
                    await store.refresh()?.value
                    XCTAssertEqual(store.snapshot?.todayTip?.actionId, alternative)
                    XCTAssertTrue(try EngineRunner.actionCommand(["reset-action-preferences", "--state-dir", isolatedState.path]))
                }
            }
        }
    }

}

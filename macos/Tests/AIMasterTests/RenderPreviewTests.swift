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
            // Use this worktree's content with real usage logs and isolated progress.
            let content = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../../content/daily.json").standardizedFileURL
            process.arguments = EngineRunner.snapshotArguments(locale: locale, tools: tools, content: content)
                + ["--state-dir", URL(fileURLWithPath: out).deletingLastPathComponent()
                    .appendingPathComponent("render-state").path]
            let pipe = Pipe(); process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return try EngineRunner.decode(data, status: process.terminationStatus)
        }
        await store.refresh()?.value
        let snap = try XCTUnwrap(store.snapshot, store.lastError ?? "no snapshot")
        XCTAssertEqual(snap.schema, 2, "Rebuild dist/365engine before rendering")
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
}

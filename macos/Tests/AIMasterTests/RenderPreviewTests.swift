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
            process.arguments = ["snapshot", "--json", "--locale", locale, "--tools", tools.joined(separator: ","),
                                 "--state-dir", URL(fileURLWithPath: out).deletingLastPathComponent()
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
            ("training", AnyView(TrainingTab(snapshot: snap)))
        ]
        for (name, tab) in views {
            let view = tab.padding(16).frame(width: 360)
                .background(Color(nsColor: .windowBackgroundColor))
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let img = try XCTUnwrap(renderer.nsImage)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(img.tiffRepresentation)))
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: out + "-" + name + ".png"))
        }
        let popover = ImageRenderer(content: PopoverView(store: store)); popover.scale = 2
        let image = try XCTUnwrap(popover.nsImage)
        XCTAssertEqual(image.size.width, 360)
        XCTAssertLessThanOrEqual(image.size.height, 600)
    }
}

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
        let view = VStack(alignment: .leading, spacing: 16) {
            if let tip = snap.todayTip { TipCard(tip: tip, store: store) }
            if let v = snap.village { VillageGrid(village: v) }
            DimensionRings(dimensions: snap.dimensions ?? [])
            UsageSection(snapshot: snap)
        }
        .padding(16).frame(width: 360).background(Color(nsColor: .windowBackgroundColor))
        let r = ImageRenderer(content: view); r.scale = 2
        let img = try XCTUnwrap(r.nsImage)
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    }
}

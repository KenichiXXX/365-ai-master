import XCTest
import SwiftUI
import Vision
@testable import AIMaster

@MainActor
final class BackgroundRefreshTests: XCTestCase {
    private func render(_ store: SnapshotStore, tab: Int) throws -> String {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(tab, forKey: "selectedTab")
        let hosting = NSHostingView(rootView: PopoverView(store: store).defaultAppStorage(defaults)
            .environment(\.locale, Locale(identifier: "en")).environment(\.colorScheme, .light))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.bounds.size, NSSize(width: 440, height: 720))
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.usesCPUOnly = true
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ").filter { !$0.isWhitespace }
    }

    private func makeStore() async throws -> (SnapshotStore, EngineResult) {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        object["locale"] = "en"
        let result = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0)
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result },
            proTrial: ProTrial(read: { nil }, write: { _ in }))
        store.actionCommand = { _ in true }
        await store.refresh()?.value
        store.dismissOnboarding()
        return (store, result)
    }

    func testTimerRefreshKeepsRenderedPicksAndTrainingIntact() async throws {
        let (store, result) = try await makeStore()
        let before = try [1, 2].map { try render(store, tab: $0) }
        XCTAssertTrue(before[0].contains("PICK"), before[0])
        XCTAssertTrue(before[1].contains("Today'straining"), before[1])
        let started = expectation(description: "timer started background refresh")
        let finished = expectation(description: "background loader finished")
        let gate = DispatchSemaphore(value: 0)
        store.load = { _, _ in
            started.fulfill()
            gate.wait()
            finished.fulfill()
            return result
        }
        defer { gate.signal() }
        // Exercise the real scheduled timer, not the manual recheck entry point.
        store.refreshSeconds = 1
        await fulfillment(of: [started], timeout: 5)
        store.refreshSeconds = 86400
        XCTAssertTrue(store.isRefreshing)
        XCTAssertNil(store.recheckScan)
        XCTAssertEqual(store.snapshotJSON, result.json)
        for (index, tab) in [1, 2].enumerated() {
            let during = try render(store, tab: tab)
            XCTAssertFalse(during.contains("Cancel"), during)
            XCTAssertFalse(during.contains("Scanningallowedsources"), during)
            XCTAssertEqual(during, before[index], "Background refresh must preserve all visible list rows")
        }
        store.cancelRefresh()
        gate.signal()
        await fulfillment(of: [finished], timeout: 3)
        for _ in 0..<100 where store.isRefreshing { await Task.yield() }
        XCTAssertFalse(store.isRefreshing)
    }

    func testManualScanAndCancelRenderOnlyOnMe() async throws {
        let (store, result) = try await makeStore()
        let started = expectation(description: "manual check started")
        let gate = DispatchSemaphore(value: 0)
        store.load = { _, _ in started.fulfill(); gate.wait(); return result }
        defer { gate.signal() }
        let task = try XCTUnwrap(store.recheck())
        await fulfillment(of: [started], timeout: 3)
        XCTAssertNotNil(store.recheckScan)
        let me = try render(store, tab: 0)
        XCTAssertTrue(me.contains("Checking"), me)
        XCTAssertTrue(me.contains("Cancel"), me)
        XCTAssertTrue(me.contains("Calculatingfourscores"), me)
        for tab in [1, 2] {
            let text = try render(store, tab: tab)
            XCTAssertFalse(text.contains("Cancel"), text)
            XCTAssertFalse(text.contains("Checking"), text)
            XCTAssertFalse(text.contains("Calculatingfourscores"), text)
        }
        store.cancelRefresh()
        gate.signal()
        await task.value
        XCTAssertNil(store.recheckScan)
        XCTAssertFalse(store.isRefreshing)
    }
}

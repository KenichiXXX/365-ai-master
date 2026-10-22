import XCTest
@testable import AIMaster

@MainActor
final class RecheckTests: XCTestCase {
    private func result(score: Int? = 69) throws -> EngineResult {
        try EngineRunner.decode(Data("""
        {"schema":3,"overall":{"score":\(score.map(String.init) ?? "null")},
         "tools":[{"tool":"claude_code","tier":"deep","detected":true},
                  {"tool":"codex","tier":"deep","detected":false}],
         "book":{"lit":0,"total":0,"cards":[],"today":{"id":"x","title":"X","why":"W","prompt":"P","level":1,"lit":false}}}
        """.utf8), status: 0)
    }

    func testTitleUsesLatestScoreAndUnlitDot() throws {
        XCTAssertEqual(StatusItemController.badgeTitle(snapshot: nil), "—")
        XCTAssertEqual(StatusItemController.badgeTitle(snapshot: try result().snapshot), "69 •")
        XCTAssertEqual(StatusItemController.badgeTitle(snapshot: try result(score: nil).snapshot), "— •")
        let lit = try EngineRunner.decode(Data(#"{"schema":3,"overall":{"score":0},"book":{"lit":1,"total":0,"cards":[],"today":{"id":"x","title":"X","why":"W","prompt":"P","level":1,"lit":true}}}"#.utf8), status: 0)
        XCTAssertEqual(StatusItemController.badgeTitle(snapshot: lit.snapshot), "0")
    }

    func testScanLinesOnlyUseDetectedEnabledTools() throws {
        let snapshot = try result().snapshot
        XCTAssertEqual(RecheckScan.lines(snapshot: snapshot, enabledTools: SnapshotStore.allTools), [.tool("claude_code"), .score])
        XCTAssertEqual(RecheckScan.lines(snapshot: snapshot, enabledTools: ["codex"]), [.score])
        XCTAssertEqual(RecheckScan.lines(snapshot: nil, enabledTools: SnapshotStore.allTools), [.score])
        XCTAssertEqual(RecheckScan.Line.tool("codex").title(locale: "zh"), "读取 Codex 记录…")
        XCTAssertEqual(RecheckScan.Line.score.title(locale: "en"), "Calculating four scores…")
    }

    func testScoreCountUpFinishesWithinEightTenthsAndSkipsReducedMotion() {
        let start = Date(timeIntervalSince1970: 100)
        let animation = ScoreCountUp(score: 69, startedAt: start)
        XCTAssertEqual(animation.value(at: start, reduceMotion: false), 0)
        XCTAssertTrue((34...35).contains(animation.value(at: start.addingTimeInterval(0.35), reduceMotion: false)!))
        XCTAssertEqual(animation.value(at: start.addingTimeInterval(0.8), reduceMotion: false), 69)
        XCTAssertEqual(animation.value(at: start, reduceMotion: true), 69)
        XCTAssertNil(ScoreCountUp(score: nil, startedAt: start).value(at: start, reduceMotion: false))
        XCTAssertEqual(ScoreCountUp(score: 69, startedAt: nil).value(at: start, reduceMotion: false), 69)
    }

    func testCancelledRecheckKeepsScoreAndClearsScan() async throws {
        let first = try result()
        let next = try result(score: 72)
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in first })
        await store.refresh()?.value
        let started = expectation(description: "recheck started")
        let gate = DispatchSemaphore(value: 0)
        store.load = { _, _ in started.fulfill(); gate.wait(); return next }
        store.cancelLoad = { gate.signal() }
        let task = store.recheck()
        await fulfillment(of: [started], timeout: 3)
        XCTAssertNotNil(store.recheckScan)
        store.cancelRefresh()
        await task?.value
        XCTAssertNil(store.recheckScan)
        XCTAssertNil(store.scoreChange)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(store.snapshot?.overall?.score, 69)
    }

    func testRecheckRunsImmediatelyAfterRefreshAndShowsScoreChange() async throws {
        let first = try result()
        let next = try result(score: 72)
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in first })
        await store.refresh()?.value
        XCTAssertEqual(store.refreshSeconds, 300)
        store.load = { _, _ in next }
        let task = try XCTUnwrap(store.recheck())
        XCTAssertNotNil(store.recheckScan)
        XCTAssertNil(store.recheck())
        await task.value
        XCTAssertNil(store.recheckScan)
        XCTAssertEqual(store.snapshot?.overall?.score, 72)
        let change = try XCTUnwrap(store.scoreChange)
        XCTAssertEqual(change.caption(locale: "zh"), "比上次 +3")
        XCTAssertEqual(change.caption(locale: "en"), "+3 since last check")
        XCTAssertTrue(change.isVisible(at: change.date.addingTimeInterval(4.99)))
        XCTAssertFalse(change.isVisible(at: change.date.addingTimeInterval(5)))
        store.load = { _, _ in first }
        await store.recheck()?.value
        XCTAssertEqual(store.scoreChange?.caption(locale: "zh"), "比上次 −3")
        store.load = { _, _ in throw EngineError.failed(2) }
        await store.recheck()?.value
        XCTAssertNil(store.recheckScan)
        XCTAssertNil(store.scoreChange)
        XCTAssertEqual(store.snapshot?.overall?.score, 69)
        XCTAssertNotNil(store.lastError)
    }
}

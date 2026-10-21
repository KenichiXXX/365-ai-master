import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class ActionCardTests: XCTestCase {
    private func unknown() throws -> EngineResult {
        try EngineRunner.decode(Data(#"{"schema":3,"overall":{"score":null,"tier":null,"availability":"partial"},"dimensions":[{"key":"routing","label":"Routing","score":null,"availability":"unknown","evidence":[]}],"today_tip":{"title":"Practice","why":"Why","steps":["Review"],"prompt_for_claude":"Draft","source":{"kind":"pool","ref":"privacy_check"},"action_id":"pool:privacy_check:1","rule_id":"pool:privacy_check","evidence_summary":"Built-in exercise","limitation":"Self report","validation_kind":"self_report"}}"#.utf8), status: 0)
    }

    func testNullScoresDecodeAndRenderAsUnknown() throws {
        let result = try unknown()
        XCTAssertNil(result.snapshot.overall?.score)
        XCTAssertNil(result.snapshot.dimensions?.first?.score)
        XCTAssertEqual(RingView(score: nil).scoreText, "—")
        XCTAssertEqual(RingView(score: 0).scoreText, "0")
        XCTAssertEqual(result.snapshot.todayTip?.evidenceSummary, "Built-in exercise")
        for locale in ["zh", "en"] {
            let renderer = ImageRenderer(content: DimensionRings(dimensions: result.snapshot.dimensions!, locale: locale).frame(width: 408))
            XCTAssertNotNil(renderer.nsImage)
        }
    }

    func testOnePrimaryActionAndReadableFeedbackLabels() throws {
        let result = try unknown()
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.dismissOnboarding()
        func countCards(_ value: Any) -> Int {
            if value is TipCard { return 1 }
            return Mirror(reflecting: value).children.reduce(0) { $0 + countCards($1.value) }
        }
        XCTAssertEqual(countCards(CheckupTab(snapshot: result.snapshot, store: store).body), 1)
        XCTAssertEqual(SnapshotStore.ActionReason.allCases.map(\.label),
                       ["I do not understand", "My tool does not support this", "I have no project", "Not useful right now"])
    }

    func testUnknownScoresNeverReportOrDisplayCachedRanking() async throws {
        let result = try unknown()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "shareAnonymousScore")
        var calls = 0
        let reporter = ScoreReporter(defaults: defaults, endpoint: URL(string: "https://local.test/v1/score")!, transport: { _ in
            calls += 1
            return (Data(#"{"score_version":"1","total":25,"rank":13,"percentile":50,"small_sample":false}"#.utf8), 200)
        })
        _ = await reporter.report(score: 80, dims: .init(routing: 80, timing: 80, context: 80, leverage: 80), appVersion: "1")
        XCTAssertEqual(calls, 1)
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result }, scoreReporter: reporter)
        XCTAssertNil(store.ranking)
        await store.refresh()?.value
        XCTAssertEqual(calls, 1)
        XCTAssertNil(store.ranking)
        XCTAssertFalse(store.rankingUnavailable)
    }

    func testFeedbackUsesCurrentAssignmentAndRefreshesPersistentResult() async throws {
        let result = try unknown()
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
        await store.refresh()?.value
        let spy = CommandSpy()
        store.actionCommand = { args in spy.record(args); return true }
        await store.actionFeedback(.later, reason: .notNow)?.value
        XCTAssertEqual(spy.commands, [["action-feedback", "pool:privacy_check:1", "later", "--reason", "not_now"]])
        await store.resetActionPreferences()?.value
        XCTAssertEqual(spy.commands.last, ["reset-action-preferences"])
        XCTAssertNil(store.lastError)
        let view = CheckupTab(snapshot: result.snapshot, store: store)
        XCTAssertNotNil(ImageRenderer(content: view.frame(width: 408)).nsImage)
    }
}

private final class CommandSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[String]] = []
    var commands: [[String]] { lock.lock(); defer { lock.unlock() }; return values }
    func record(_ args: [String]) { lock.lock(); defer { lock.unlock() }; values.append(args) }
}

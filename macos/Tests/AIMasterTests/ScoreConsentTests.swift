import XCTest
import SwiftUI
@testable import AIMaster

final class ScoreConsentTests: XCTestCase {
    // Inspect the value tree produced by the banner's ViewBuilder, without launching the app.
    private func containsPanel(_ value: Any) -> Bool {
        if value is ScoreConsentPanel { return true }
        return Mirror(reflecting: value).children.contains { containsPanel($0.value) }
    }

    private func containsText(_ text: Text, in value: Any) -> Bool {
        if let candidate = value as? Text { return candidate == text }
        return Mirror(reflecting: value).children.contains { containsText(text, in: $0.value) }
    }

    @MainActor func testBannerConsentStaysInsideBannerAndRankLinkConsentDoesNot() {
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        func banner(_ source: ScoreConsentSource?) -> CheckupOnboardingBanner {
            CheckupOnboardingBanner(store: store, zh: true, consentSource: source,
                                    requestConsent: {}, closeConsent: {})
        }
        XCTAssertFalse(containsPanel(banner(nil).body))
        XCTAssertTrue(containsPanel(banner(.banner).body))
        XCTAssertFalse(containsPanel(banner(.rankLink).body))
        XCTAssertTrue(containsText(Text("知道了"), in: banner(nil).body))
        XCTAssertFalse(containsText(Text("知道了"), in: banner(.banner).body))
    }

    @MainActor func testAllowOptsInDismissesAndReportsExactlyOnce() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        // A failed attempt today must not prevent the first successful opt-in report.
        defaults.set(Date(), forKey: "scoreReportedAt")
        var calls = 0
        let reporter = ScoreReporter(defaults: defaults, transport: { _ in
            calls += 1
            return (Data(#"{"total":25,"rank":13,"percentile":50,"small_sample":false}"#.utf8), 200)
        })
        let result = try snapshotResult()
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result }, scoreReporter: reporter)
        await store.refresh()?.value
        XCTAssertEqual(calls, 0)
        await store.allowScoreSharing()
        XCTAssertTrue(store.shareAnonymousScore)
        XCTAssertTrue(defaults.bool(forKey: "shareAnonymousScore"))
        XCTAssertTrue(store.onboarded)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.ranking?.percentile, 50)
        XCTAssertEqual(store.rankingCaption(locale: "en"), "You beat 50% of AI users (25 taking part)")
        await store.allowScoreSharing()
        await store.refresh()?.value
        XCTAssertEqual(calls, 1, "Allow and refresh must preserve the daily gate after success")
    }

    @MainActor func testAllowShowsFetchingThenFailure() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var response: CheckedContinuation<(Data, Int), Error>?
        let reporter = ScoreReporter(defaults: defaults, transport: { _ in
            try await withCheckedThrowingContinuation { response = $0 }
        })
        let result = try snapshotResult()
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result }, scoreReporter: reporter)
        await store.refresh()?.value
        let allow = Task { await store.allowScoreSharing() }
        // Let the request reach the deliberately suspended fake transport.
        for _ in 0..<100 where response == nil { await Task.yield() }
        guard let response else { XCTFail("Allow did not start reporting"); return }
        XCTAssertTrue(store.shareAnonymousScore)
        XCTAssertTrue(store.onboarded)
        XCTAssertEqual(store.rankingCaption(locale: "zh"), "正在获取排名…")
        XCTAssertEqual(store.rankingCaption(locale: "en"), "Fetching your ranking…")
        response.resume(returning: (Data(), 503))
        await allow.value
        XCTAssertNil(store.ranking)
        XCTAssertEqual(store.rankingCaption(locale: "zh"), "暂时连不上排名服务")
        XCTAssertEqual(store.rankingCaption(locale: "en"), "Ranking service unavailable")
    }

    @MainActor func testAllowPreservesDailyGateEvenAfterSuccessfulCacheWasCleared() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "shareAnonymousScore")
        let now = Date()
        var calls = 0
        let reporter = ScoreReporter(defaults: defaults, transport: { _ in
            calls += 1
            return calls == 1
                ? (Data(#"{"total":1,"rank":1,"percentile":null,"small_sample":true}"#.utf8), 200)
                : (Data(), 503)
        })
        let dims = ScoreReporter.Dims(routing: 60, timing: 70, context: 80, leverage: 90)
        _ = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now.addingTimeInterval(-86400))
        _ = await reporter.report(score: 75, dims: dims, appVersion: "1.0", now: now)
        XCTAssertEqual(calls, 2)
        XCTAssertNil(reporter.cached())
        defaults.set(false, forKey: "shareAnonymousScore")
        let result = try snapshotResult()
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result }, scoreReporter: reporter)
        await store.refresh()?.value
        await store.allowScoreSharing()
        XCTAssertEqual(calls, 2, "A prior successful report must prevent the first-consent bypass")
    }

    private func snapshotResult() throws -> EngineResult {
        return try EngineRunner.decode(Data("""
        {"schema":2,"overall":{"score":75,"tier":"test"},"dimensions":[
        {"key":"routing","label":"Routing","score":60},{"key":"timing","label":"Timing","score":70},
        {"key":"context","label":"Context","score":80},{"key":"leverage","label":"Leverage","score":90}]}
        """.utf8), status: 0)
    }

}

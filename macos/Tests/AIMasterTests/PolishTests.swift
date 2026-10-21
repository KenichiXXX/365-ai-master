import XCTest
@testable import AIMaster

final class PolishTests: XCTestCase {
    func testRankingGrowthStringsAndOptionalMetrics() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let row = try decoder.decode(Ranking.self, from: Data("""
        {"name":"a/b","url":"https://example.org","tagline":"B","installed":true,"stars":302000,"stars7d":3946}
        """.utf8))
        XCTAssertEqual(row.growth(locale: "zh"), "★ 30.2万 · 本周 +3,946")
        XCTAssertEqual(row.growth(locale: "en"), "★ 302K · +3,946 this week")
        let noWeek = Ranking(name: "B", url: "", tagline: "", installed: false, stars: 302000, stars7d: nil)
        XCTAssertEqual(noWeek.growth(locale: "en"), "★ 302K")
        XCTAssertEqual(Ranking(name: "B", url: "", tagline: "", installed: false).growth(locale: "en"), "")
        let zero = Ranking(name: "B", url: "", tagline: "", installed: false, stars: 0, stars7d: 0)
        XCTAssertEqual(zero.growth(locale: "en"), "★ 0 · +0 this week")
        XCTAssertEqual(Ranking(name: "B", url: "", tagline: "", installed: false, stars: 120000000).growth(locale: "zh"), "★ 1.2亿")
    }

    func testCopyFeedbackExpiresAndRepeatedCopyRestartsIt() {
        var feedback = CopyFeedback()
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(feedback.isCopied(at: start))
        feedback.markCopied(at: start)
        XCTAssertTrue(feedback.isCopied(at: start.addingTimeInterval(1.49)))
        XCTAssertFalse(feedback.isCopied(at: start.addingTimeInterval(1.5)))
        feedback.markCopied(at: start.addingTimeInterval(1))
        XCTAssertTrue(feedback.isCopied(at: start.addingTimeInterval(2)))
        XCTAssertFalse(feedback.isCopied(at: start.addingTimeInterval(2.5)))
    }

    @MainActor func testOnboardingPersistsAndRefreshDefaults() {
        let defaults = UserDefaults(suiteName: "polish-" + UUID().uuidString)!
        let store = SnapshotStore(defaults: defaults)
        XCTAssertFalse(store.onboarded)
        XCTAssertEqual(store.refreshSeconds, 300)
        store.dismissOnboarding()
        XCTAssertTrue(SnapshotStore(defaults: defaults).onboarded)
        for seconds in [60, 300, 900] {
            defaults.set(seconds, forKey: "refreshSeconds")
            XCTAssertEqual(SnapshotStore(defaults: defaults).refreshSeconds, seconds)
        }
        defaults.set(30, forKey: "refreshSeconds")
        XCTAssertEqual(SnapshotStore(defaults: defaults).refreshSeconds, 300)
    }

    @MainActor func testTriedFeedbackUsesFreshLogsAndSelfReport() async throws {
        let defaults = UserDefaults(suiteName: "tried-" + UUID().uuidString)!
        let unlit = try result(lit: false)
        let lit = try result(lit: true)
        let store = SnapshotStore(defaults: defaults, load: { _, _ in unlit },
                                  tryCard: { _ in XCTFail("Log cards must only rescan"); return false })
        let logCard = SkillCard(id: "s", title: "S", why: "W", prompt: "P", level: 1,
                                lit: false, how: nil, detect: "tool:WebSearch")
        await store.markTried(logCard)?.value
        XCTAssertEqual(store.triedFeedback, .notSeen)
        store.load = { _, _ in lit }
        await store.markTried(logCard)?.value
        XCTAssertEqual(store.triedFeedback, .lit)
        let selfCard = SkillCard(id: "s", title: "S", why: "W", prompt: "P", level: 1,
                                 lit: false, how: nil, detect: "self")
        store.tryCard = { id in XCTAssertEqual(id, "s"); return true }
        await store.markTried(selfCard)?.value
        XCTAssertEqual(store.triedFeedback, .lit)
        store.tryCard = { _ in false }
        await store.markTried(selfCard)?.value
        XCTAssertNil(store.triedFeedback)
        XCTAssertNotNil(store.lastError)
        store.load = { _, _ in throw EngineError.failed(2) }
        await store.markTried(logCard)?.value
        XCTAssertNil(store.triedFeedback)
        XCTAssertNotNil(store.lastError)
    }

    private func result(lit: Bool) throws -> EngineResult {
        try EngineRunner.decode(Data("""
        {"schema":2,"book":{"lit":0,"total":1,"cards":[{"id":"s","title":"S","why":"W","prompt":"P","level":1,"lit":\(lit)}]}}
        """.utf8), status: 0)
    }
}

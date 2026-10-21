import XCTest
@testable import AIMaster

final class V2Tests: XCTestCase {
    func testCompactTokensAndSummary() {
        XCTAssertEqual(UsageSummary.tokens(28_670_000, locale: "zh"), "2,867 万")
        XCTAssertEqual(UsageSummary.tokens(28_670_000, locale: "en"), "28.7M")
        XCTAssertEqual(UsageSummary.tokens(100_000_000, locale: "zh"), "1.0 亿")
        XCTAssertEqual(UsageSummary.tokens(29_442_000, locale: "zh"), "2,944 万")
        XCTAssertEqual(UsageSummary.tokens(120_000_000, locale: "zh"), "1.2 亿")
        XCTAssertEqual(UsageSummary.tokens(10_000, locale: "zh"), "1 万")
        XCTAssertEqual(UsageSummary.tokens(9_999, locale: "zh"), "9999")
        XCTAssertEqual(UsageSummary.tokens(1_200, locale: "en"), "1.2K")
        XCTAssertEqual(UsageSummary.tokens(2_000_000_000, locale: "en"), "2B")
        let usage = UsageSummary(tokens7d: 28_670_000, costUsd7d: 577, codexQuotaPct: 13)
        XCTAssertEqual(usage.caption(locale: "zh"), "日志 Token（不含缓存读取）: 2,867 万 · 价格未知 · 按公开 API 单价折算，非订阅账单")
        XCTAssertEqual(usage.caption(locale: "en"), "Logged tokens (excluding cache reads): 28.7M · Price unknown · API-equivalent at public prices, not a subscription bill")
        XCTAssertFalse(UsageSummary(tokens7d: 0, costUsd7d: 0, codexQuotaPct: nil).caption(locale: "en").contains("Codex"))
    }

    func testContentArgumentOnlyWhenFileExists() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../.pytest_cache/args-" + UUID().uuidString + ".json")
        let base = EngineRunner.snapshotArguments(locale: "zh", tools: ["codex"], content: file)
        XCTAssertFalse(base.contains("--content"))
        try Data("{}".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(EngineRunner.snapshotArguments(locale: "zh", tools: ["codex"], content: file),
                       base + ["--content", file.path])
    }

    func testV1AndOptionalRankingSource() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let v1 = try EngineRunner.decode(Data("{\"schema\":1}".utf8), status: 0).snapshot
        XCTAssertNil(v1.book)
        let data = Data("{\"schema\":2,\"rankings\":{\"source\":\"The Skill Leaderboard · GitHub\"}}".utf8)
        let v2 = try decoder.decode(Snapshot.self, from: data)
        XCTAssertEqual(v2.rankings?.source, "The Skill Leaderboard · GitHub")
        XCTAssertEqual(try EngineRunner.decode(data, status: 0).snapshot.schema, 2)
    }

    @MainActor func testMenuBadgeUsesUnlitSkill() throws {
        for (lit, suffix) in [(false, " •"), (true, "")] {
            let data = Data("""
            {"schema":2,"book":{"lit":0,"total":1,"cards":[],"today":{"id":"s","title":"S","why":"W","prompt":"P","level":1,"lit":\(lit)}},"village":{"current":"q","rank_title":"R","quests":[{"key":"q","title":"Q","status":"current"}]}}
            """.utf8)
            XCTAssertEqual(StatusItemController.badgeTitle(snapshot: try EngineRunner.decode(data, status: 0).snapshot), "①" + suffix)
        }
    }
}

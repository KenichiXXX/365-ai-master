import XCTest
@testable import AIMaster

final class UsageSectionTests: XCTestCase {
    func testCompactUsageAndTopModels() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let snapshot = try decoder.decode(Snapshot.self, from: Data("""
        {"schema":1,"locale":"en","tools":[
          {"tool":"empty","tier":"usage","detected":true,"usage_7d":{"tokens":0,"cost_usd":0}},
          {"tool":"codex","tier":"deep","detected":true,"usage_today":{"tokens":307695,"cost_usd":10},"usage_7d":{"tokens":646737,"cost_usd":241.08},"by_model":[
            {"model":"a","tokens":1,"cost_usd":0},{"model":"b","tokens":4,"cost_usd":0},
            {"model":"c","tokens":3,"cost_usd":0},{"model":"d","tokens":2,"cost_usd":0}]}]}
        """.utf8))
        let view = UsageSection(snapshot: snapshot)
        XCTAssertEqual(view.visibleTools.map(\.tool), ["codex"])
        let tool = try XCTUnwrap(view.visibleTools.first)
        XCTAssertEqual(view.summary(tool), "Today 307,695 · 7d 646,737 tokens · ≈$241.08 (API-equivalent)")
        XCTAssertEqual(view.topModels(tool).map(\.model), ["b", "c", "d"])
    }

    func testQuotaWindowAndResetLabels() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        for (locale, minutes, expected) in [
            ("en", 10080, "Codex weekly 12% · resets Oct 27"),
            ("zh", 10080, "Codex 周额度 12% · 10月27日重置"),
            ("en", 300, "Codex 5h 12% · resets Oct 27"),
            ("zh", 300, "Codex 5 小时额度 12% · 10月27日重置"),
            ("en", 120, "Codex 2h 12% · resets Oct 27")
        ] {
            let snapshot = try decoder.decode(Snapshot.self, from: Data("""
            {"schema":1,"locale":"\(locale)","quota":{"codex":{"primary_pct":12,"primary_window_min":\(minutes),"primary_resets_at":"2026-10-27T12:00:00Z"}}}
            """.utf8))
            let view = UsageSection(snapshot: snapshot)
            XCTAssertEqual(view.quotaLabel(try XCTUnwrap(snapshot.quota?.codex)), expected)
        }
    }
}

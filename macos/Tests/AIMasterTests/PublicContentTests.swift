import XCTest
@testable import AIMaster

final class PublicContentTests: XCTestCase {
    static func package() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("content/daily.json"))) as! [String: Any]
    }
    func testFullPackageAndMalformedSections() throws {
        let valid = try Self.package()
        XCTAssertTrue(PublicContent.validate(valid))
        for field in ["review_exercises", "rankings", "tips"] {
            var invalid = valid; invalid.removeValue(forKey: field)
            XCTAssertFalse(PublicContent.validate(invalid), field)
        }
        var invalid = valid
        var cards = valid["skills"] as! [[String: Any]]
        cards[0]["validator"] = "execute:shell"; invalid["skills"] = cards
        XCTAssertFalse(PublicContent.validate(invalid))
        cards = valid["skills"] as! [[String: Any]]
        cards[0]["detect"] = "tool:WebSearch\n"; invalid["skills"] = cards
        XCTAssertFalse(PublicContent.validate(invalid))
        invalid = valid
        var ranks = valid["rankings"] as! [String: Any]
        var rows = ranks["skill"] as! [[String: Any]]
        rows[0]["source_type"] = 7; ranks["skill"] = rows; invalid["rankings"] = ranks
        XCTAssertFalse(PublicContent.validate(invalid))
        invalid = valid; invalid["prices"] = ["models": []]
        XCTAssertFalse(PublicContent.validate(invalid))
        invalid = valid; invalid["tool_updates"] = [["id": "invented"]]
        XCTAssertFalse(PublicContent.validate(invalid))
    }
    func testOptionalUpdatesAreValidatedAndHiddenWithoutMatchingCoverage() throws {
        var package = try Self.package()
        let update: [String: Any] = ["id": "fixture-only", "tool": "codex", "source_url": "https://github.com/openai/codex/releases/tag/test-fixture",
            "fetched_at": "2026-10-21", "released_at": "2026-10-20", "compatibility": ["format": "codex-response-usage-v1", "adapter_versions": ["1"]],
            "summary": ["zh": "测试数据", "en": "Test fixture"], "practice_id": (package["skills"] as! [[String: Any]])[0]["id"]!]
        package["tool_updates"] = [update]
        XCTAssertTrue(PublicContent.validate(package))
        for (key, value) in [("source_url", "https://github.com/openai/codex/issues/1" as Any), ("released_at", "2026-10-22"), ("compatibility", ["format": "codex-response-usage-v1", "adapter_versions": ["*"]])] {
            var bad = update; bad[key] = value; package["tool_updates"] = [bad]
            XCTAssertFalse(PublicContent.validate(package), key)
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        var snapshot: [String: Any] = ["schema": 3, "tool_updates": [["id": "fixture", "tool": "codex", "source_url": update["source_url"]!, "fetched_at": "2026-10-21", "released_at": "2026-10-20", "summary": "Fixture", "practice_id": "practice", "compatibility": update["compatibility"]!]], "tools": [["tool": "codex", "tier": "deep", "detected": true]], "coverage": ["codex": ["adapter_version": "1", "format": "codex-response-usage-v1", "status": "ok", "valid_usage_count": 1, "malformed_count": 0, "skipped_count": 0, "signals": [:]]]]
        func decode() throws -> Snapshot { try decoder.decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: snapshot)) }
        XCTAssertEqual(try decode().relevantToolUpdates.count, 1)
        snapshot["coverage"] = ["codex": ["adapter_version": "2", "format": "codex-response-usage-v1", "status": "ok", "valid_usage_count": 1, "malformed_count": 0, "skipped_count": 0, "signals": [:]]]
        XCTAssertTrue(try decode().relevantToolUpdates.isEmpty)
        snapshot.removeValue(forKey: "coverage")
        XCTAssertTrue(try decode().relevantToolUpdates.isEmpty)
    }

    func testStablePublicURLs() {
        for value in ["http://example.com/a", "https://localhost/a", "https://127.0.0.1/a", "https://192.168.0.1/a", "https://[::1]/a", "https://user:pass@example.com/a", "https://example.com/a?q=1", "https://example.com/a#fragment"] {
            XCTAssertFalse(PublicContent.safeURL(value), value)
        }
        XCTAssertTrue(PublicContent.safeURL("https://github.com/openai/codex"))
    }
    func testRankingMetadataAndSourceLabels() throws {
        let data = Data(#"{"skill":[],"origin":"bundled","updated_at":"2026-10-21"}"#.utf8)
        let rankings = try JSONDecoder().decode(Rankings.self, from: data)
        XCTAssertEqual(rankings.sourceLabel(locale: "en"), "Bundled selection, not a live leaderboard")
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let row = try decoder.decode(Ranking.self, from: Data(#"{"name":"test","url":"https://example.com/a","tagline":"test","installed":false,"installation_hint":true}"#.utf8))
        XCTAssertEqual(row.compatibilityLabel(locale: "en"), "Compatibility unknown")
        XCTAssertTrue(row.installationHint == true)
    }
}

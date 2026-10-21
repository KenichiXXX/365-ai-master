import XCTest
@testable import AIMaster
final class SnapshotDecodingTests: XCTestCase {
    func testDecodesEngineFixture() throws {
        let url = Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures")!
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let s = try dec.decode(Snapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(s.schema, 3)
        XCTAssertNotNil(s.book?.today)
        XCTAssertGreaterThan(s.book?.total ?? 0, 0)
        XCTAssertNotNil(s.usageSummary?.tokens7d)
        XCTAssertNotNil(s.rankings?.skill)
        XCTAssertNotNil(s.dailyTip)
        XCTAssertNotNil(s.streak)
        XCTAssertNotNil(s.badges)
        let claude = try XCTUnwrap(s.tools?.first { $0.tool == "claude_code" })
        XCTAssertNotNil(claude.usage7d)
        XCTAssertGreaterThan(claude.usage7d?.tokens ?? 0, 0)
        XCTAssertNotNil(claude.usageToday)
        XCTAssertEqual(s.locale, "zh")
        XCTAssertFalse(s.labels?.noTools.isEmpty ?? true)
        XCTAssertEqual(s.village?.quests.count, 9)
        XCTAssertFalse(s.todayTip?.promptForClaude.isEmpty ?? true)
        XCTAssertEqual(s.quota?.codex?.primaryPct, 42.5)
    }
    func testDecodesMissingPrimaryQuota() throws {
        let data = Data("{\"schema\":1,\"quota\":{\"codex\":{\"primary_pct\":null,\"secondary_pct\":10}}}".utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        XCTAssertNil(snapshot.quota?.codex?.primaryPct)
        XCTAssertEqual(snapshot.quota?.codex?.secondaryPct, 10)
    }
    func testSchemaThreeCoverageAndLegacyMigration() throws {
        for schema in [1, 2, 3] {
            let data = Data("""
            {"schema": \(schema), "coverage": {"claude_code": {
              "adapter_version":"1", "format":"claude-jsonl-v1", "status":"partial",
              "start_utc":null,"end_utc":null,"valid_usage_count":1,
              "malformed_count":1,"skipped_count":2,"signals":{"usage":"unknown"}}}}
            """.utf8)
            let result = try EngineRunner.decode(data, status: 0)
            XCTAssertEqual(result.snapshot.coverage?["claude_code"]?.status, .partial)
            XCTAssertEqual(result.snapshot.coverage?["claude_code"]?.validUsageCount, 1)
        }
        XCTAssertThrowsError(try EngineRunner.decode(Data("{\"schema\":4}".utf8), status: 0))
        let legacy = try EngineRunner.decode(Data("{\"schema\":1}".utf8), status: 0)
        XCTAssertNil(legacy.snapshot.coverage)
    }
}

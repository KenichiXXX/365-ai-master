import XCTest
@testable import AIMaster
final class SnapshotDecodingTests: XCTestCase {
    func testDecodesEngineFixture() throws {
        let url = Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures")!
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let s = try dec.decode(Snapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(s.schema, 1)
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
}

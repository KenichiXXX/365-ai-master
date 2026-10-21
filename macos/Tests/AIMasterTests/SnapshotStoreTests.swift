import XCTest
@testable import AIMaster

final class SnapshotStoreTests: XCTestCase {
    func testRunnerRejectsFailureAndUnsupportedSchema() throws {
        XCTAssertThrowsError(try EngineRunner.decode(Data("{\"schema\":1,\"error\":\"ValueError\"}".utf8), status: 2))
        XCTAssertThrowsError(try EngineRunner.decode(Data("not json".utf8), status: 0))
        XCTAssertThrowsError(try EngineRunner.decode(Data("{\"schema\":2}".utf8), status: 0))
        XCTAssertThrowsError(try EngineRunner.decode(Data("{\"schema\":1,\"error\":\"ValueError\"}".utf8), status: 0))
    }

    @MainActor func testFailedRefreshKeepsSnapshotAndTimestamp() async throws {
        let url = Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures")!
        let result = try EngineRunner.decode(Data(contentsOf: url), status: 0)
        let defaults = UserDefaults(suiteName: "AIMasterTests")!
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result })
        await store.refresh()?.value
        let lastRun = store.lastRun
        XCTAssertEqual(store.snapshot?.schema, 1)
        XCTAssertNotNil(lastRun)
        XCTAssertTrue(store.snapshotJSON.contains("inventory"))
        store.load = { _, _ in throw EngineError.failed(2) }
        await store.refresh()?.value
        XCTAssertEqual(store.snapshot?.schema, 1)
        XCTAssertEqual(store.lastRun, lastRun)
        XCTAssertNotNil(store.lastError)
    }

    @MainActor func testMenuBadgeUsesQuestAndNoData() throws {
        XCTAssertEqual(StatusItemController.badgeTitle(snapshot: nil), "○")
        let data = Data("{\"schema\":1,\"village\":{\"current\":null,\"rank_title\":\"Master\",\"quests\":[]}}".utf8)
        XCTAssertEqual(StatusItemController.badgeTitle(snapshot: try EngineRunner.decode(data, status: 0).snapshot), "✓")
    }
}

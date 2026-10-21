import XCTest
@testable import AIMaster

final class ContentUpdaterTests: XCTestCase {
    @MainActor func testValidationAndOnceDailyFetch() async throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../.pytest_cache/content-updater-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("content.json")
        let defaults = UserDefaults(suiteName: "ContentUpdaterTests-" + UUID().uuidString)!
        let valid = try JSONSerialization.data(withJSONObject: PublicContentTests.package())
        try valid.write(to: file)
        for (status, data) in [(503, valid), (200, Data(repeating: 32, count: 1_000_001)),
                               (200, Data("{\"version\":2,\"skills\":[{}]}".utf8)),
                               (200, Data("{\"version\":1,\"skills\":[]}".utf8)),
                               (200, Data("bad json".utf8))] {
            defaults.removeObject(forKey: "contentAttemptedAt")
            let updater = ContentUpdater(file: file, defaults: defaults, loader: { (data, status) })
            let changed = await updater.refreshIfNeeded()
            XCTAssertFalse(changed)
            XCTAssertEqual(try Data(contentsOf: file), valid)
            XCTAssertNil(defaults.object(forKey: "contentFetchedAt"))
        }
        defaults.removeObject(forKey: "contentAttemptedAt")
        var calls = 0
        let updater = ContentUpdater(file: file, defaults: defaults, loader: {
            calls += 1; return (valid, 200)
        })
        let changed = await updater.refreshIfNeeded()
        XCTAssertTrue(changed)
        _ = await updater.refreshIfNeeded()
        XCTAssertEqual(calls, 1)
        let rollback = Date(timeIntervalSinceNow: -86400)
        _ = await updater.refreshIfNeeded(now: rollback)
        XCTAssertEqual(calls, 1)
        defaults.set(Date(timeIntervalSinceNow: -172800), forKey: "contentAttemptedAt")
        _ = await updater.refreshIfNeeded()
        XCTAssertEqual(calls, 2)
        var failedCalls = 0
        let failure = ContentUpdater(file: file, defaults: UserDefaults(suiteName: UUID().uuidString)!, loader: {
            failedCalls += 1
            throw NSError(domain: "offline", code: 1)
        })
        let failed = await failure.refreshIfNeeded()
        XCTAssertFalse(failed)
        _ = await failure.refreshIfNeeded()
        XCTAssertEqual(failedCalls, 1)
        XCTAssertTrue(failure.stale)
        let staleDefaults = UserDefaults(suiteName: UUID().uuidString)!
        staleDefaults.set(Date(), forKey: "contentAttemptedAt")
        let restarted = ContentUpdater(file: file, defaults: staleDefaults, loader: { (valid, 200) })
        XCTAssertTrue(restarted.stale)
        XCTAssertEqual(try Data(contentsOf: file), valid)
    }
}

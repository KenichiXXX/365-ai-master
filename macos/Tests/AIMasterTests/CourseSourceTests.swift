import XCTest
@testable import AIMaster

final class CourseSourceTests: XCTestCase {
    @MainActor func testStoreKeepsCodeLocalAndCheckoutSelectionSeparate() async throws {
        let prefs = UserDefaults(suiteName: UUID().uuidString)!
        let raw = Data(#"{"course_sources":[{"code":"SYNTHETIC_1","practice_id":"web_search","title":{"zh":"合成课程","en":"Synthetic course"}}]}"#.utf8)
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent(".pytest_cache/task35-source-" + UUID().uuidString + ".json")
        try raw.write(to: file)
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let result = try EngineRunner.decode(Data(contentsOf: fixture), status: 0)
        let store = SnapshotStore(defaults: prefs, load: { _, _ in result }, courseContentURL: file)
        store.courseSourceCode = "SYNTHETIC_1"
        await store.refresh()?.value
        XCTAssertEqual(store.courseSource?.practiceID, "web_search")
        XCTAssertNil(store.checkoutSource)
        XCTAssertFalse(store.includeCourseSource)
        XCTAssertFalse(store.shareAnonymousScore)
        XCTAssertFalse(store.autoRefreshLicense)
        store.includeCourseSource = true
        XCTAssertEqual(store.checkoutSource?.code, "SYNTHETIC_1")
        store.courseSourceCode = "unknown"
        XCTAssertFalse(store.includeCourseSource)
        XCTAssertNil(store.checkoutSource)
        XCTAssertNil(store.courseCard)
        store.courseSourceCode = "SYNTHETIC_1"
        store.includeCourseSource = true
        let restart = SnapshotStore(defaults: prefs, load: { _, _ in result }, courseContentURL: file)
        await restart.refresh()?.value
        XCTAssertEqual(restart.courseSourceCode, "SYNTHETIC_1")
        XCTAssertNotNil(restart.courseCard)
        XCTAssertNil(restart.checkoutSource, "Selection is per checkout, never a persisted consent")
        XCTAssertEqual(EngineRunner.courseSources(practiceIDs: ["web_search"], content: file).count, 1)
    }

    func testReviewedBoundedCatalogueAndExplicitCheckoutSelection() throws {
        let raw = Data(#"{"course_sources":[{"code":"SYNTHETIC_1","practice_id":"web_search","title":{"zh":"合成课程","en":"Synthetic course"}}]}"#.utf8)
        let catalogue = CourseSource.catalogue(raw, practiceIDs: ["web_search"])
        XCTAssertEqual(catalogue.count, 1)
        let entry = try XCTUnwrap(CourseSource.match("SYNTHETIC_1", in: catalogue))
        XCTAssertEqual(entry.practiceID, "web_search")
        XCTAssertNil(CourseSource.match("unknown", in: catalogue))
        XCTAssertNil(CourseSource.match("", in: catalogue))
        XCTAssertNil(CourseSource.match("bad&key=secret", in: catalogue))
        XCTAssertTrue(CourseSource.catalogue(raw, practiceIDs: []).isEmpty)
        XCTAssertTrue(CourseSource.catalogue(Data(#"{"course_sources":[]}"#.utf8), practiceIDs: []).isEmpty)
        XCTAssertTrue(CourseSource.catalogue(Data(repeating: 0, count: 2_000_001), practiceIDs: []).isEmpty)
        let config = PurchaseConfiguration(checkout: URL(string: "https://merchant.example/pay"), management: URL(string: "https://merchant.example/manage"),
            allowedHosts: ["merchant.example"], verifiedIntegration: true, verifiedTerms: true)
        XCTAssertNil(config.checkout(source: nil)?.query)
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(config.checkout(source: entry)), resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "source", value: "SYNTHETIC_1")])
        let card = SkillCard(id: "web_search", title: "Search", why: "Why", prompt: "Prompt", level: 1, lit: false, how: nil)
        XCTAssertTrue(ProFeatures(isPro: false, coursePracticeID: entry.practiceID).canLearn(card, todayID: "other"))
        XCTAssertFalse(ProFeatures(isPro: false).canLearn(card, todayID: "other"))
    }
}

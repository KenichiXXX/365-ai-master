import XCTest
@testable import AIMaster

@MainActor
final class PracticeTests: XCTestCase {
    func testEvidenceLabelsAreDistinctAndDoNotDependOnPurchase() throws {
        for kind in ["ready", "started", "historical", "configuration", "self_reported", "log_observed", "reuse"] {
            let data = Data("""
            {"schema":3,"book":{"lit":1,"total":24,"cards":[{"id":"a","title":"A","why":"Try",
            "prompt":"Try","level":1,"lit":true,"how":"log","evidence_kind":"\(kind)",
            "validator":"self","automatic_supported":false}],"yesterday":[{"attempt_id":"1","skill_id":"a","status":"coverage_missing"}]}}
            """.utf8)
            let book = try XCTUnwrap(EngineRunner.decode(data, status: 0).snapshot.book)
            let card = try XCTUnwrap(book.cards.first)
            XCTAssertFalse(card.evidenceText(locale: "zh").isEmpty)
            XCTAssertNotEqual(card.evidenceText(locale: "zh"), card.evidenceText(locale: "en"))
            XCTAssertEqual(book.yesterday?.first?.status, "coverage_missing")
            for pro in [false, true] {
                _ = ProFeatures(isPro: pro)
                XCTAssertTrue(card.lit)
                XCTAssertEqual(card.evidenceKind, kind)
            }
        }
    }

    func testFeedbackIsScopedAndCopyUsesExplicitCommand() async throws {
        let data = Data("""
        {"schema":3,"book":{"lit":0,"total":24,"cards":[]}}
        """.utf8)
        let result = try EngineRunner.decode(data, status: 0)
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
        store.actionCommand = { args in args == ["practice", "web_search", "copy"] }
        await store.practice(id: "web_search", operation: "copy")?.value
        XCTAssertEqual(store.practiceFeedbackID, "web_search")
        XCTAssertNil(store.feedback(for: "other"))
        XCTAssertNotNil(store.feedback(for: "web_search"))
    }
}

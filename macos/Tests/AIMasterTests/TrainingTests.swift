import XCTest
@testable import AIMaster

final class TrainingTests: XCTestCase {
    func testTrainingSnapshotContract() throws {
        let data = Data("""
        {"schema":2,"book":{"lit":1,"total":24,"cards":[],
          "groups":[{"level":1,"title":"Basics","lit":1,"total":8,"missing":["web_search"]},
                    {"level":2,"title":"Intermediate","lit":0,"total":10,"missing":[]},
                    {"level":3,"title":"Advanced","lit":0,"total":6,"missing":[]}],
          "next_badge":{"id":"streak_3","title":"3-day streak","have":2,"need":3}}}
        """.utf8)
        let book = try XCTUnwrap(EngineRunner.decode(data, status: 0).snapshot.book)
        XCTAssertEqual(book.groups?.map(\.level), [1, 2, 3])
        XCTAssertEqual(book.groups?.first?.missing, ["web_search"])
        XCTAssertEqual(book.groups?.first?.title, "Basics")
        XCTAssertEqual(book.groups?.first?.lit, 1)
        XCTAssertEqual(book.groups?.first?.total, 8)
        XCTAssertEqual(book.nextBadge?.id, "streak_3")
        XCTAssertEqual(book.nextBadge?.title, "3-day streak")
        XCTAssertEqual(book.nextBadge?.have, 2)
        XCTAssertEqual(book.nextBadge?.need, 3)
    }

    func testOlderBookAndAllBadgesEarned() throws {
        for suffix in ["", ",\"next_badge\":null"] {
            let data = Data("{\"schema\":2,\"book\":{\"lit\":24,\"total\":24,\"cards\":[]\(suffix)}}".utf8)
            let book = try XCTUnwrap(EngineRunner.decode(data, status: 0).snapshot.book)
            XCTAssertNil(book.groups)
            XCTAssertNil(book.nextBadge)
        }
    }
}

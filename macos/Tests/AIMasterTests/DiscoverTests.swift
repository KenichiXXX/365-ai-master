import XCTest
import SwiftUI
@testable import AIMaster

final class DiscoverTests: XCTestCase {
    func testRecommendationsMatchWeakestAvailableDimensionAndExcludeInstalled() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = Data(#"{"schema":3,"dimensions":[{"key":"context","label":"Context","score":null},{"key":"routing","label":"Routing","score":20},{"key":"leverage","label":"Leverage","score":70}],"rankings":{"skill":[{"name":"installed","url":"https://example.com/a","tagline":"Installed","task_category":"model","installation_hint":true},{"name":"wrong","url":"https://example.com/b","tagline":"Memory","task_category":"memory"}],"agent":[{"name":"agent","url":"https://example.com/c","tagline":"Agent","task_category":"agent"},{"name":"model","url":"https://example.com/d","tagline":"Model","task_category":"model"},{"name":"extra","url":"https://example.com/e","tagline":"Extra","task_category":"model"}],"product":[]}}"#.utf8)
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        XCTAssertEqual(DiscoverContent.picks(snapshot).map(\.name), ["agent", "model"])
        XCTAssertEqual(DiscoverContent.reason(dimension: "routing", locale: "zh"), "让不同模型各展所长")
        XCTAssertEqual(snapshot.rankings?.product?.count, 0)
    }

    func testCategoryMapAndNoGuessedRecommendations() throws {
        XCTAssertEqual(DiscoverContent.categories["routing"], ["model", "agent"])
        XCTAssertEqual(DiscoverContent.categories["context"], ["memory", "context"])
        XCTAssertEqual(DiscoverContent.categories["leverage"], ["skills", "automation"])
        XCTAssertEqual(DiscoverContent.categories["timing"], ["productivity", "automation"])
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"schema":3}"#.utf8))
        XCTAssertTrue(DiscoverContent.picks(snapshot).isEmpty)
    }

    func testAllFourRankingsRespectFreeAndProLimits() {
        XCTAssertEqual(DiscoverRanking.allCases.count, 4)
        let rows = (0..<24).map { Ranking(name: "\($0)", url: "https://example.com/a", tagline: "Fixture") }
        XCTAssertEqual(ProFeatures(isPro: false).discoverRankings(rows).count, 10)
        XCTAssertEqual(ProFeatures(isPro: true).discoverRankings(rows).count, 20)
    }

    func testProductValidationRejectsMalformedAndTooShortLists() throws {
        var package = try PublicContentTests.package()
        var rankings = package["rankings"] as! [String: Any]
        XCTAssertEqual((rankings["product"] as? [[String: Any]])?.count, 11)
        rankings["product"] = [["name": "bad"]]; package["rankings"] = rankings
        XCTAssertFalse(PublicContent.validate(package))
    }
}

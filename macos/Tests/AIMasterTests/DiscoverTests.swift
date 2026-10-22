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

    @MainActor
    func testFourRankingsRenderInBothLanguages() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        for locale in ["zh", "en"] {
            var object = base
            object["locale"] = locale
            let rows = (1...20).map { i in
                ["name": "fixture/\(i)", "url": "https://example.com/\(i)",
                 "tagline": locale == "zh" ? "帮助你更轻松地编程" : "Make coding easier",
                 "stars": 298000, "stars7d": 9302, "installed": i == 1] as [String: Any]
            }
            object["rankings"] = ["origin": "cached", "skill": rows, "agent": rows, "product": rows]
            let result = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0)
            let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
            await store.refresh()?.value
            for ranking in DiscoverRanking.allCases {
                let hosting = NSHostingView(rootView: TodaySkillTab(snapshot: result.snapshot, store: store, ranking: ranking)
                    .padding(16).frame(width: 440).environment(\.locale, Locale(identifier: locale))
                    .environment(\.colorScheme, .light).background(Color.white))
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                hosting.layoutSubtreeIfNeeded()
                XCTAssertEqual(hosting.bounds.width, 440)
                XCTAssertGreaterThan(hosting.bounds.height, 100)
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                if let out = ProcessInfo.processInfo.environment["RENDER_OUT"] {
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                        URL(fileURLWithPath: out + "-discover-" + ranking.rawValue + "-" + locale + ".png"))
                }
            }
        }
    }

    func testProductValidationRejectsMalformedAndTooShortLists() throws {
        var package = try PublicContentTests.package()
        var rankings = package["rankings"] as! [String: Any]
        XCTAssertEqual((rankings["product"] as? [[String: Any]])?.count, 11)
        rankings["product"] = [["name": "bad"]]; package["rankings"] = rankings
        XCTAssertFalse(PublicContent.validate(package))
    }
}

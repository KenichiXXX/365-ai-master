import XCTest
import SwiftUI
@testable import AIMaster

final class ZeroTokenTests: XCTestCase {
    func testHonestBilingualPromise() {
        XCTAssertEqual(AnalysisPromise.title(locale: "zh"), "怎么算的")
        XCTAssertEqual(AnalysisPromise.title(locale: "en"), "How it works")
        XCTAssertEqual(AnalysisPromise.caption, "0 token")
        XCTAssertEqual(AnalysisPromise.lines(locale: "zh"), ["只读本机日志", "规则计算，不调用任何 AI", "不消耗你的 token 额度", "不上传（除非你开启排名/榜单下载）"])
        XCTAssertEqual(AnalysisPromise.lines(locale: "en").count, 4)
        XCTAssertTrue(AnalysisPromise.lines(locale: "en")[3].contains("rankings"))
    }

    func testJevFieldsDecodeAndBeginnerMatchesComeFirst() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let snapshot = try decoder.decode(Snapshot.self, from: Data(#"{"schema":3,"dimensions":[{"key":"routing","label":"Routing","score":20}],"rankings":{"skill":[{"name":"legacy","url":"https://example.com/legacy","tagline":"Legacy","task_category":"model"},{"name":"hard","url":"https://example.com/hard","tagline":"Hard","category":"coding","beginner":2},{"name":"easy","url":"https://example.com/easy","tagline":"Easy","category":"coding","beginner":4},{"name":"wrong","url":"https://example.com/wrong","tagline":"Wrong","category":"memory","beginner":5},{"name":"installed","url":"https://example.com/installed","tagline":"Installed","category":"coding","beginner":5,"installation_hint":true},{"name":"duplicate","url":"https://example.com/easy","tagline":"Duplicate","category":"coding","beginner":5}]}}"#.utf8))
        let easy = try XCTUnwrap(snapshot.rankings?.skill?[2])
        XCTAssertEqual(easy.category, "coding")
        XCTAssertEqual(easy.beginner, 4)
        XCTAssertEqual(easy.beginnerTag(locale: "zh"), "新手友好")
        XCTAssertEqual(easy.beginnerTag(locale: "en"), "Beginner friendly")
        XCTAssertNil(snapshot.rankings?.skill?[1].beginnerTag(locale: "en"))
        XCTAssertEqual(DiscoverContent.picks(snapshot).map(\.name), ["easy", "legacy"])
    }

    func testPublicFieldsValidation() throws {
        var content = try PublicContentTests.package()
        var rankings = content["rankings"] as! [String: Any]
        var skills = rankings["skill"] as! [[String: Any]]
        skills[0]["category"] = "memory"; skills[0]["beginner"] = 4
        rankings["skill"] = skills; content["rankings"] = rankings
        XCTAssertTrue(PublicContent.validate(content))
        for bad in [true, 0, 6, 3.5, "4"] as [Any] {
            skills[0]["beginner"] = bad
            rankings["skill"] = skills; content["rankings"] = rankings
            XCTAssertFalse(PublicContent.validate(content))
        }
    }

    func testAllWeakestDimensionsPreferMatchingBeginnerItems() throws {
        for (dimension, category) in [("routing", "coding"), ("context", "memory"),
                                      ("leverage", "browser"), ("timing", "automation")] {
            let object: [String: Any] = ["schema": 3,
                "dimensions": [["key": dimension, "label": dimension, "score": 10]],
                "rankings": ["skill": [
                    ["name": "hard", "url": "https://example.com/hard", "tagline": "Hard", "category": category, "beginner": 2],
                    ["name": "start", "url": "https://example.com/start", "tagline": "Start", "category": category, "beginner": 3]]]]
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(DiscoverContent.picks(snapshot).map(\.name), ["start"], dimension)
            XCTAssertNil(snapshot.rankings?.skill?.last?.beginnerTag(locale: "zh"))
        }
    }

}

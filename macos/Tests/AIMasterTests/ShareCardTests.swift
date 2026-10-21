import XCTest
import ImageIO
@testable import AIMaster

@MainActor
final class ShareCardTests: XCTestCase {
    func testWhitelistRejectsPrivateStringsAndDefaultsToNoScore() throws {
        XCTAssertNil(ReviewedCapability(rawValue: "/private/project"))
        XCTAssertNil(ShareEvidence(rawValue: "license-secret"))
        XCTAssertThrowsError(try SharePeriod(start: "2026-02-30", end: "2026-10-21"))
        let period = try SharePeriod(start: "2026-10-01", end: "2026-10-21")
        let card = ShareCardInput(period: period, capabilities: [.init(capability: .web_search, evidence: .reuse)])
        XCTAssertNil(card.score)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["period", "capabilities"])
        let row = try XCTUnwrap((object["capabilities"] as? [[String: String]])?.first)
        XCTAssertEqual(row, ["capability": "web_search", "evidence": "reuse"])
        XCTAssertThrowsError(try ShareScore(value: 101, coverage: period))
    }

    func testDeterministicPNGHasNoPrivateMetadataAndSaveCanCancel() throws {
        let card = ShareCardInput(period: try SharePeriod(start: "2026-10-01", end: "2026-10-21"),
                                  capabilities: [.init(capability: .web_search, evidence: .log_observed)])
        let first = try ShareCardRenderer.png(card, locale: "en")
        XCTAssertEqual(first, try ShareCardRenderer.png(card, locale: "en"))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(first as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        for forbidden in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
            XCTAssertNil(properties[forbidden as String])
        }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../.build/share-cancel").standardizedFileURL
        XCTAssertFalse(try ShareCardRenderer.save(first, chooseURL: { nil }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../.build/share-test.png").standardizedFileURL
        XCTAssertTrue(try ShareCardRenderer.save(first, chooseURL: { url }))
        XCTAssertEqual(try Data(contentsOf: url), first)
    }

    func testUntrustedSnapshotTextNeverEntersCard() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        var book = try XCTUnwrap(object["book"] as? [String: Any])
        var cards = try XCTUnwrap(book["cards"] as? [[String: Any]])
        for index in cards.indices {
            cards[index]["title"] = "https://tracking.invalid/private-sentinel"
            cards[index]["prompt"] = "/private/user/license-sentinel"
            cards[index]["evidence_kind"] = "log_observed"
            cards[index]["evidence_label"] = "conversation-sentinel"
        }
        book["cards"] = cards
        object["book"] = book
        let snapshot = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0).snapshot
        let input = try XCTUnwrap(ShareCardInput.from(snapshot, includeScore: false))
        XCTAssertFalse(input.capabilities.isEmpty)
        let exported = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        for sentinel in ["tracking.invalid", "/private", "license-sentinel", "conversation-sentinel"] {
            XCTAssertFalse(exported.contains(sentinel))
        }
    }

    func testRenderShareCardsInBothLanguages() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        let period = try SharePeriod(start: "2026-10-01", end: "2026-10-21")
        for locale in ["zh", "en"] {
            let entries = ReviewedCapability.allCases.map { ShareCardInput.Entry(capability: $0, evidence: .reuse) }
            for withScore in [false, true] {
                let card = ShareCardInput(period: period, capabilities: entries,
                    score: withScore ? try ShareScore(value: 82, coverage: period) : nil)
                try ShareCardRenderer.png(card, locale: locale).write(to: URL(fileURLWithPath: out + "-share-" + locale + "-" + String(withScore) + ".png"))
            }
        }
    }
}

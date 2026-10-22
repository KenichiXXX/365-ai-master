import XCTest
import SwiftUI
import Vision
@testable import AIMaster

final class MasterPicksTests: XCTestCase {
    func testShortNamesKeepOwnersOnlyWhenAmbiguousAcrossTheWholeList() {
        let rows = ["alice/helper", "bob/Helper", "carol/unique", "plain"].map {
            Ranking(name: $0, url: "https://example.com/\($0)", tagline: "Fixture")
        }
        XCTAssertEqual(rows.map { DiscoverContent.shortName($0, in: rows) },
                       ["alice/helper", "bob/Helper", "unique", "plain"])
        let list = (1...10).map { Ranking(name: "owner/tool\($0)", url: "https://example.com/\($0)", tagline: "") }
            + [Ranking(name: "other/tool1", url: "https://example.com/other", tagline: "")]
        XCTAssertEqual(DiscoverContent.shortName(list[0], in: list), "owner/tool1")
    }

    func testMetricPrefersActualWeeklyDataIncludingZeroAndDecline() {
        var row = Ranking(name: "tool", url: "https://example.com/tool", tagline: "", stars: 220000)
        XCTAssertEqual(DiscoverContent.metric(row, locale: "zh"), "★ 22万")
        XCTAssertEqual(DiscoverContent.metric(row, locale: "en"), "★ 220K")
        row.stars7d = 8990
        XCTAssertEqual(DiscoverContent.metric(row, locale: "zh"), "▲ 8,990")
        row.stars = nil
        XCTAssertEqual(DiscoverContent.metric(row, locale: "en"), "▲ 8,990")
        row.stars7d = 0
        XCTAssertEqual(DiscoverContent.metric(row, locale: "en"), "= 0")
        row.stars7d = -23
        XCTAssertEqual(DiscoverContent.metric(row, locale: "en"), "▼ 23")
        row.stars7d = nil
        XCTAssertEqual(DiscoverContent.metric(row, locale: "en"), "")
    }

    func testLocksOnlyExistingHiddenRowsAndAllFourTabsAreCompact() {
        XCTAssertEqual(DiscoverRanking.allCases.map { $0.title(zh: true) }, ["Skill", "Agent", "技能", "产品"])
        for count in [0, 10, 11, 20, 24] {
            XCTAssertEqual(DiscoverContent.hasLockedRows(count: count, isPro: false), count > 10)
            XCTAssertFalse(DiscoverContent.hasLockedRows(count: count, isPro: true))
        }
    }

    @MainActor
    func testPremiumRankingsRenderFreeAndProWithoutLeakingLockedNames() throws {
        for locale in ["zh", "en"] {
            let rows = (1...20).map { index in
                ["name": "owner/\(index == 11 ? "HiddenEleven" : index == 20 ? "HiddenTwenty" : "Tool\(index)")",
                 "url": "https://example.com/\(index)", "tagline": "One useful action",
                 "stars": 220000, "stars7d": 8990, "installed": index == 1] as [String: Any]
            }
            let cards = (1...20).map { index in
                ["id": "s\(index)", "title": "Practice\(index)", "why": "Remember what matters",
                 "prompt": "Try this", "level": 1, "lit": false] as [String: Any]
            }
            let object: [String: Any] = ["schema": 3, "locale": locale,
                "book": ["lit": 0, "total": 20, "today": cards[0], "cards": cards],
                "rankings": ["origin": "bundled", "skill": rows, "agent": rows, "product": rows]]
            let snapshot = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0).snapshot
            for pro in [false, true] {
                var trialData: Data?
                let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                    proTrial: ProTrial(read: { trialData }, write: { trialData = $0 }))
                if pro { store.startProTrial() }
                XCTAssertEqual(store.isPro, pro)
                for kind in DiscoverRanking.allCases {
                    for scheme in [ColorScheme.light, .dark] {
                        let renderer = ImageRenderer(content: TodaySkillTab(snapshot: snapshot, store: store, ranking: kind)
                            .padding(16).frame(width: 440).environment(\.colorScheme, scheme))
                        let image = try XCTUnwrap(renderer.cgImage)
                        if let output = ProcessInfo.processInfo.environment["RENDER_OUT"] {
                            let bitmap = NSBitmapImageRep(cgImage: image)
                            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                                URL(fileURLWithPath: output + "-\(locale)-\(pro ? "pro" : "free")-\(kind.rawValue)-\(scheme).png"))
                        }
                        XCTAssertEqual(image.width, 440)
                        XCTAssertGreaterThan(image.height, 100)
                        if !pro { XCTAssertLessThanOrEqual(image.height, 1500) }
                        if locale == "en", kind == .skill, scheme == .light {
                            let request = VNRecognizeTextRequest()
                            request.usesCPUOnly = true
                            request.recognitionLevel = .accurate
                            request.recognitionLanguages = ["en-US"]
                            try VNImageRequestHandler(cgImage: image).perform([request])
                            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                            XCTAssertTrue(text.contains("PICK"), text)
                            XCTAssertTrue(text.contains("8,990"), text)
                            XCTAssertEqual(text.contains("PRO"), !pro, text)
                            XCTAssertEqual(text.filter { !$0.isWhitespace }.contains("HiddenEleven"), pro, text)
                            XCTAssertEqual(text.filter { !$0.isWhitespace }.contains("HiddenTwenty"), pro, text)
                        }
                    }
                }
            }
        }
    }
}

import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class DeclutterTests: XCTestCase {
    // Inspect the declared visible tree, excluding menu/disclosure contents.
    private func actionCount(_ value: Any) -> Int {
        let type = String(describing: type(of: value))
        if type.hasPrefix("Menu<") || type.hasPrefix("DisclosureGroup<") { return 0 }
        if value is CopyButton || type.hasPrefix("Button<") { return 1 }
        return Mirror(reflecting: value).children.reduce(0) { $0 + actionCount($1.value) }
    }

    func testPracticeHasOneVisibleActionAndTipHasTwo() throws {
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let card = SkillCard(id: "s", title: "S", why: "W", prompt: "P", level: 1,
                             lit: false, how: nil, detect: "self")
        XCTAssertEqual(actionCount(PracticeControls(card: card, store: store, locale: "zh").body), 1)
        let result = try EngineRunner.decode(Data(#"{"schema":3,"today_tip":{"title":"T","why":"W","steps":["S"],"prompt_for_claude":"P","source":{"kind":"pool","ref":"s"},"action_id":"pool:s:1","validation_kind":"self_report"}}"#.utf8), status: 0)
        XCTAssertEqual(actionCount(TipCard(tip: result.snapshot.todayTip!, store: store).body), 2)
    }

    func testManualPracticeHasOnlyTwoVisibleActions() {
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.dismissOnboarding()
        XCTAssertEqual(actionCount(FirstPracticeView(store: store, locale: "zh").body), 2)
    }

    func testUsageCaptionIsCompactAndNeverShowsRawTimestamps() throws {
        let result = try EngineRunner.decode(Data(#"{"schema":3,"usage_summary":{"tokens_7d":29570000,"cost_usd_7d":null,"price_estimate":{"matched_subtotal_usd":735,"coverage_pct":100,"reviewed_at":"2026-10-21"},"codex_quota":{"primary_pct":42,"primary_window_min":300,"secondary_pct":27,"secondary_window_min":10080,"secondary_resets_at":"2026-10-27T06:49:00Z","recorded_at":"2026-10-22T00:00:00Z","freshness":"fresh"}}}"#.utf8), status: 0)
        let usage = try XCTUnwrap(result.snapshot.usageSummary)
        for locale in ["zh", "en"] {
            let caption = usage.caption(locale: locale)
            XCTAssertTrue(caption.hasPrefix(locale == "zh" ? "本周 2,957 万 tokens · 折算 $735" : "This week 29.6M tokens · ≈$735 API-equivalent"), caption)
            XCTAssertTrue(caption.contains(locale == "zh" ? "Codex 周额度 27%" : "Codex weekly 27%"), caption)
            XCTAssertFalse(caption.contains("2026-"), caption)
            XCTAssertFalse(caption.contains("42%"), caption)
            XCTAssertFalse(caption.contains("\n"))
            XCTAssertLessThan(caption.count, locale == "zh" ? 90 : 120)
        }
    }

    func testDatesUseLocalizedShortFormatsIncludingFractionalTimestamps() {
        let zone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(DisplayDate.short("2026-10-27T06:49:00Z", locale: "zh", timeZone: zone), "10月27日 15:49")
        XCTAssertEqual(DisplayDate.short("2026-10-27T06:49:00.123Z", locale: "en", timeZone: zone)
            .replacingOccurrences(of: "\u{202F}", with: " "), "Oct 27 at 3:49 PM")
        XCTAssertEqual(DisplayDate.short("2026-10-27", locale: "en", timeZone: zone), "Oct 27")
        XCTAssertEqual(DisplayDate.short("not-a-date", locale: "zh"), "—")
    }

    func testRankingFootnotesAreOncePerListAndDoNotExposeTransportDates() throws {
        for origin in ["bundled", "cached"] {
            let rankings = try JSONDecoder().decode(Rankings.self,
                from: Data("{\"origin\":\"\(origin)\",\"updatedAt\":\"2026-10-21\"}".utf8))
            XCTAssertEqual(rankings.footnote(locale: "zh"), origin == "bundled" ? "内置精选"
                : "数据：The Skill Leaderboard · GitHub · 安装前请自行核对权限")
            XCTAssertLessThanOrEqual(rankings.footnote(locale: "en").count, 80)
        }
    }

    func testTodayWithTopFiveListsFitsHeightBudget() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        for locale in ["zh", "en"] {
            var object = base
            object["locale"] = locale
            let rows = (1...5).map { index in
                ["name": "example/skill-\(index)", "url": "https://github.com/example/skill-\(index)",
                 "tagline": locale == "zh" ? "在真实任务中练习与检查" : "Practise and check in real tasks",
                 "stars": 298000, "stars7d": 9302, "installed": index == 1,
                 "source_url": "https://github.com/example/skill-\(index)", "source_type": "curated",
                 "caution": "Check permissions and source before installing"] as [String: Any]
            }
            object["rankings"] = ["origin": "bundled", "skill": rows, "agent": rows]
            let result = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0)
            let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
            let renderer = ImageRenderer(content: TodaySkillTab(snapshot: result.snapshot, store: store)
                .padding(16).frame(width: 440).environment(\.locale, Locale(identifier: locale)))
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, 440)
            XCTAssertLessThanOrEqual(image.size.height, 1500)
        }
    }
}

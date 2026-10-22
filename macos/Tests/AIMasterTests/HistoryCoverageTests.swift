import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class HistoryCoverageTests: XCTestCase {
    private func snapshot() throws -> Snapshot {
        try EngineRunner.decode(Data(#"{"schema":3,"locale":"en","growth":{"days":[{"date":"2026-10-16","score":60,"score_version":"v1"},{"date":"2026-10-17","score":65,"score_version":"v1"},{"date":"2026-10-18","score":null},{"date":"2026-10-19","score":70,"score_version":"v1"},{"date":"2026-10-20","score":80,"score_version":"v2"},{"date":"2026-10-21","score":85,"score_version":"v2"}],"week_delta":null,"comparison":{"reason":"version_changed"}},"weekly":{"week_start":"2026-10-19","score_delta":null,"cards_lit_this_week":[],"quests_passed_this_week":[],"days_active":0,"observed_change":{"text":"No new practice change was observed this week","metric_id":"practice.new_observations","evidence_ids":[]},"uncertainty":{"text":"Collecting comparable data","reason":"incomplete_window"},"next_practice":{"text":"One practice for next week","practice_id":"web_search"},"report_text":"No new practice change was observed this week\nCollecting comparable data\nOne practice for next week: web_search"},"usage_summary":{"tokens_7d":150,"cost_usd_7d":null,"price_estimate":{"matched_subtotal_usd":0.00064,"coverage_pct":95,"reviewed_at":"2026-10-21"},"codex_quota":{"primary_pct":42,"primary_window_min":300,"primary_resets_at":"2026-10-22T00:00:00Z","secondary_pct":25,"secondary_window_min":10080},"labels":{"tokens":"Logged tokens (excluding cache reads)","price_basis":"API-equivalent at public prices, not a subscription bill","matched_subtotal":"Matched subtotal USD {amount}, price coverage {pct}%","price_unknown":"Price unknown","price_date":"Price table dated {date}","quota_hours":"Codex {hours}-hour window: {pct}% used","quota_week":"Codex weekly window: {pct}% used"}}}"#.utf8), status: 0).snapshot
    }

    func testSegmentsBreakOnMissingDatesAndVersionsAndDeltaIsUnknown() throws {
        let s = try snapshot()
        XCTAssertEqual(s.growth?.segments.map { $0.map(\.date) }, [
            ["2026-10-16", "2026-10-17"], ["2026-10-19"], ["2026-10-20", "2026-10-21"]])
        XCTAssertNil(s.growth?.weekDelta)
        XCTAssertNil(s.weekly?.scoreDelta)
        XCTAssertTrue(s.weekly!.summary(locale: "en").contains("Collecting comparable data"))
        XCTAssertFalse(s.weekly!.reportText!.contains("/"))
    }

    func testAbsentDatesAndLegacyVersionsRemainIsolated() throws {
        let data = Data(#"{"schema":3,"growth":{"days":[{"date":"2026-10-16","score":60,"score_version":"v1"},{"date":"2026-10-18","score":65,"score_version":"v1"},{"date":"2026-10-19","score":70,"score_version":"legacy_unknown_version"},{"date":"2026-10-20","score":80,"score_version":"v1"}],"week_delta":44}}"#.utf8)
        let growth = try XCTUnwrap(EngineRunner.decode(data, status: 0).snapshot.growth)
        XCTAssertEqual(growth.segments.map(\.count), [1, 1, 1, 1])
        XCTAssertNil(growth.comparableDelta) // unversioned old deltas are never shown
    }

    func testQuotaUsesRecordedDurationAndPartialPriceWording() throws {
        let usage = try XCTUnwrap(snapshot().usageSummary)
        let caption = usage.details(locale: "en")
        XCTAssertTrue(caption.contains("5-hour window: 42%"))
        XCTAssertTrue(caption.contains("weekly window: 25%"))
        XCTAssertTrue(caption.contains("Matched subtotal USD"))
        XCTAssertTrue(caption.contains("not a subscription bill"))
        XCTAssertFalse(caption.contains("saved"))
        XCTAssertEqual(usage.codexQuota?.primaryResetsAt, "2026-10-22T00:00:00Z")
        for locale in ["zh", "en"] {
            let legacy = UsageSummary(tokens7d: 100, costUsd7d: 10, codexQuotaPct: 42)
            let text = legacy.details(locale: locale)
            XCTAssertFalse(text.contains("42%")) // no duration, no invented weekly window
            XCTAssertTrue(text.contains(locale == "zh" ? "价格未知" : "Price unknown"))
            XCTAssertFalse(text.contains("节省"))
        }
    }

    func testRenderGapVersionBreakAndAccumulatingReview() throws {
        let snapshot = try snapshot()
        for locale in ["zh", "en"] {
            let view = VStack(alignment: .leading) {
                TrendChart(growth: snapshot.growth!).frame(height: 120)
                Text(snapshot.weekly!.summary(locale: locale))
                Text(snapshot.weekly!.observedChange!.text)
                Text(snapshot.weekly!.nextPractice!.text)
            }.padding(20).frame(width: 440).background(Color(nsColor: .windowBackgroundColor))
            let renderer = ImageRenderer(content: view)
            let image = try XCTUnwrap(renderer.nsImage)
            if let out = ProcessInfo.processInfo.environment["RENDER_OUT"] {
                let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: out + "-history-" + locale + ".png"))
            }
        }
    }
}

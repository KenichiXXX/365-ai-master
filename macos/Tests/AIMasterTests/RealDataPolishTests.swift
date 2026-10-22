import XCTest
@testable import AIMaster

final class RealDataPolishTests: XCTestCase {
    func testWeeklyQuotaMarkerUsesRecordTimeAndWindow() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        for (age, resetOffset, expected) in [
            (7200.0, 5 * 86400.0, ""),
            (8 * 86400.0, 5 * 86400.0, "stale"),
            (-60.0, 5 * 86400.0, "future"),
            (7200.0, -3600.0, "stale")
        ] {
            let recorded = iso.string(from: now.addingTimeInterval(-age))
            let reset = iso.string(from: now.addingTimeInterval(resetOffset))
            // A stale legacy flag for a shorter window must not taint the weekly caption.
            let data = Data("""
            {"schema":3,"usage_summary":{"tokens_7d":100,"cost_usd_7d":null,
            "codex_quota":{"primary_pct":42,"primary_window_min":300,
            "primary_resets_at":"2026-10-22T11:00:00Z","secondary_pct":29,
            "secondary_window_min":10080,"secondary_resets_at":"\(reset)",
            "recorded_at":"\(recorded)","freshness":"future"}}}
            """.utf8)
            let usage = try XCTUnwrap(EngineRunner.decode(data, status: 0).snapshot.usageSummary)
            for locale in ["zh", "en"] {
                let caption = usage.caption(locale: locale)
                XCTAssertTrue(caption.contains(locale == "zh" ? "Codex 周额度 29%" : "Codex weekly 29%"))
                XCTAssertEqual(caption.contains(locale == "zh" ? "时间异常" : "future-dated"), expected == "future", caption)
                XCTAssertEqual(caption.contains(locale == "zh" ? "过时" : "stale"), expected == "stale", caption)
                XCTAssertFalse(caption.contains("2026-"))
                if expected.isEmpty {
                    XCTAssertTrue(caption.contains(DisplayDate.short(reset, locale: locale, time: false)), caption)
                }
            }
        }
    }

    func testPartialPriceDetailsDiscloseUnknownModels() throws {
        let data = Data(#"{"schema":3,"usage_summary":{"tokens_7d":100,"cost_usd_7d":null,"price_estimate":{"matched_subtotal_usd":12,"coverage_pct":80,"reviewed_at":null}}}"#.utf8)
        let usage = try XCTUnwrap(EngineRunner.decode(data, status: 0).snapshot.usageSummary)
        XCTAssertTrue(usage.caption(locale: "zh").contains("部分折算 $12"))
        XCTAssertTrue(usage.details(locale: "zh").contains("部分模型价格未知"))
        XCTAssertTrue(usage.details(locale: "en").contains("Some model prices are unknown"))
    }
}

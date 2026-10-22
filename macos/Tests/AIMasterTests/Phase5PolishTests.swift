import XCTest
@testable import AIMaster

final class Phase5PolishTests: XCTestCase {
    func testSettingsVersionAndFriendlyIntervals() throws {
        XCTAssertEqual(SettingsView.versionLabel(locale: "zh"), "开发版")
        XCTAssertEqual(SettingsView.versionLabel(locale: "en"), "Dev build")
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../.pytest_cache/task47-" + UUID().uuidString + ".app")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..")
        try Data(contentsOf: root.appendingPathComponent("macos/Info.plist"))
            .write(to: directory.appendingPathComponent("Contents/Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: directory))
        XCTAssertEqual(SettingsView.versionLabel(bundle: bundle, locale: "en"), "Version 0.4.0")
        XCTAssertEqual(SettingsView.versionLabel(bundle: bundle, locale: "zh"), "版本 0.4.0")
        XCTAssertEqual(SnapshotStore.refreshIntervals.map { SettingsView.intervalLabel($0, locale: "zh") },
                       ["1 分钟", "5 分钟", "15 分钟"])
        XCTAssertEqual(SnapshotStore.refreshIntervals.map { SettingsView.intervalLabel($0, locale: "en") },
                       ["1 min", "5 min", "15 min"])
    }

    func testDisabledDownloadsIgnoreExistingCache() throws {
        let cache = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../content/daily.json")
        let enabled = EngineRunner.snapshotArguments(locale: "zh", tools: [], content: cache)
        XCTAssertTrue(enabled.contains(cache.path))
        let disabled = EngineRunner.snapshotArguments(locale: "zh", tools: [], content: nil)
        XCTAssertFalse(disabled.contains("--content"))
        let bundled = try JSONDecoder().decode(Rankings.self, from: Data(#"{"origin":"bundled"}"#.utf8))
        XCTAssertEqual(bundled.footnote(locale: "zh"), "内置精选")
    }

    func testUsageCaptionRoundsToWholeGroupedDollars() throws {
        for coverage in [100, 50] {
            let result = try EngineRunner.decode(Data("""
            {"schema":3,"usage_summary":{"tokens_7d":100,"price_estimate":{"matched_subtotal_usd":1049.49,"coverage_pct":\(coverage),"reviewed_at":"2026-10-22"}}}
            """.utf8), status: 0)
            for locale in ["zh", "en"] {
                let caption = try XCTUnwrap(result.snapshot.usageSummary).caption(locale: locale)
                XCTAssertTrue(caption.contains("$1,049"), caption)
                XCTAssertFalse(caption.contains(".49"), caption)
                if coverage < 100 { XCTAssertTrue(caption.contains(locale == "zh" ? "部分" : "partial")) }
            }
        }
    }

    @MainActor func testDailyRankingsDefaultOnAndExplicitOffPersists() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SnapshotStore(defaults: defaults)
        XCTAssertEqual(store.publicDownloads, true)
        store.publicDownloads = false
        XCTAssertEqual(SnapshotStore(defaults: defaults).publicDownloads, false)
    }

    func testLiveShapedRankingMetricsSurviveSnapshotDecoding() throws {
        let package = try PublicContentTests.package()
        var rankings = try XCTUnwrap(package["rankings"] as? [String: Any])
        for kind in ["skill", "agent", "product"] {
            var rows = try XCTUnwrap(rankings[kind] as? [[String: Any]])
            XCTAssertFalse(rows.isEmpty)
            rows = rows.map { row in
                var row = row
                row["tagline"] = (row["tagline"] as? [String: String])?["zh"] ?? "测试榜单"
                row["caution"] = (row["caution"] as? [String: String])?["zh"]
                row["stars"] = 298000
                row["stars7d"] = 9302
                return row
            }
            rankings[kind] = rows
        }
        let data = try JSONSerialization.data(withJSONObject: ["schema": 3, "rankings": rankings])
        let decoded = try XCTUnwrap(EngineRunner.decode(data, status: 0).snapshot.rankings)
        for row in (decoded.skill ?? []) + (decoded.agent ?? []) + (decoded.product ?? []) {
            XCTAssertEqual(row.growth(locale: "zh"), "★ 29.8万 · 本周 +9,302")
            XCTAssertEqual(row.growth(locale: "en"), "★ 298K · +9,302 this week")
        }
    }
}

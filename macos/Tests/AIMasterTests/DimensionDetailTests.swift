import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class DimensionDetailTests: XCTestCase {
    func testScoreTitlesUseScoreRatherThanQuestProgress() {
        for (score, title) in [(90, "AI 宗师"), (89, "AI 大师"), (75, "AI 大师"),
                               (74, "AI 熟练者"), (60, "AI 熟练者"), (59, "AI 探索者")] {
            XCTAssertEqual(CheckupPresentation.title(score: score, locale: "zh"), title)
        }
        XCTAssertNil(CheckupPresentation.title(score: nil, locale: "en"))
        XCTAssertEqual(CheckupPresentation.title(score: 90, locale: "en"), "AI Grandmaster")
    }

    func testDetailsDecodeNewAndLegacyEvidenceAndRenderBothTiers() throws {
        let data = Data(#"{"schema":3,"dimensions":[{"key":"routing","label":"模型分工","score":75,"verdict":"轻量模型用得少","evidence":[{"label":"轻量模型占比","value":"0%","target":">5%"}],"deductions":[{"title":"轻量模型用得少","points":20}],"steps":["把简单任务交给轻量模型"],"prompt":"帮我选模型"}],"growth":{"days":[{"date":"2026-10-21","score":69,"score_version":"1","rule_version":"1","dims":{"routing":75}},{"date":"2026-10-22","score":70,"score_version":"1","rule_version":"1","dims":{"routing":null}}]}}"#.utf8)
        let snapshot = try EngineRunner.decode(data, status: 0).snapshot
        let dimension = try XCTUnwrap(snapshot.dimensions?.first)
        XCTAssertEqual(dimension.verdict, "轻量模型用得少")
        XCTAssertEqual(dimension.evidence?.first?.value, "0%")
        XCTAssertEqual(dimension.deductions?.first?.points, 20)
        XCTAssertEqual(snapshot.growth?.forDimension("routing").segments.map(\.count), [1])
        XCTAssertEqual(snapshot.growth?.forDimension("routing").days.first?.score, 75)
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for locale in ["zh", "en"] {
            for pro in [false, true] {
                let view = DimensionDetail(dimension: dimension, growth: snapshot.growth,
                    features: ProFeatures(isPro: pro), locale: locale, store: store, back: {})
                let image = ImageRenderer(content: view.padding(16).frame(width: 440)).nsImage
                XCTAssertNotNil(image)
            }
        }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        XCTAssertNotNil(try EngineRunner.decode(Data(contentsOf: fixture), status: 0).snapshot.dimensions)
    }

    func testRankingCardKeepsExactSampleAndRank() {
        let ranking = AppScoreOut(total: 20, rank: 4, percentile: 80, small_sample: false)
        XCTAssertEqual(CheckupPresentation.rankCaption(ranking, locale: "zh"), "打败了全球 80% 的 AI 用户")
        XCTAssertEqual(CheckupPresentation.participants(ranking, locale: "zh"), "20 人参与 · 第 4 名")
        XCTAssertEqual(CheckupPresentation.rankCaption(AppScoreOut(total: 19, rank: 4, percentile: nil, small_sample: true), locale: "zh"), "早期排名：19 人中第 4 名")
    }

    func testRenderRealDimensionDetails() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else {
            throw XCTSkip("set RENDER_OUT")
        }
        for locale in ["zh", "en"] {
            let process = Process()
            process.executableURL = try XCTUnwrap(EngineRunner.engineURL())
            process.arguments = ["snapshot", "--json", "--locale", locale,
                                 "--state-dir", out + "-dimension-state-" + locale]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let result = try EngineRunner.decode(data, status: process.terminationStatus)
            let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                      load: { _, _ in result })
            let dimensions = try XCTUnwrap(result.snapshot.dimensions)
            XCTAssertEqual(dimensions.count, 4)
            for dimension in dimensions {
                XCTAssertFalse(try XCTUnwrap(dimension.evidence).isEmpty)
                for pro in [false, true] {
                    let view = DimensionDetail(dimension: dimension, growth: result.snapshot.growth,
                        features: ProFeatures(isPro: pro), locale: locale, store: store, back: {})
                    let renderer = ImageRenderer(content: view.padding(16).frame(width: 440)
                        .environment(\.locale, Locale(identifier: locale))
                        .background(Color(nsColor: .windowBackgroundColor)))
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.nsImage)
                    XCTAssertEqual(image.size.width, 440)
                    let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                    try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to:
                        URL(fileURLWithPath: out + "-dimension-" + dimension.key + "-" + locale
                            + (pro ? "-pro" : "-free") + ".png"))
                }
            }
        }
    }
}

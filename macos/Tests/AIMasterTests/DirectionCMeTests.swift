import XCTest
import SwiftUI
import Vision
@testable import AIMaster

@MainActor
final class DirectionCMeTests: XCTestCase {
    private func render<V: View>(_ view: V, scheme: ColorScheme, width: CGFloat = 400) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        bitmap.size = hosting.bounds.size
        return bitmap
    }

    private func accentPixels(_ bitmap: NSBitmapImageRep, scheme: ColorScheme) throws -> Int {
        let expected = scheme == .light ? [0.0, 127, 117] : [101.0, 220, 198]
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if zip([color.redComponent, color.greenComponent, color.blueComponent], expected)
                    .allSatisfy({ abs($0 - $1 / 255) < 0.03 }) { count += 1 }
            }
        }
        return Int(Double(count) / pow(Double(bitmap.pixelsWide) / bitmap.size.width, 2))
    }

    func testScoreIsTealRingRatherThanSolidDiskInBothAppearances() throws {
        let snapshot = try EngineRunner.decode(Data(#"{"schema":3,"overall":{"score":69}}"#.utf8), status: 0).snapshot
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for scheme in [ColorScheme.light, .dark] {
            let bitmap = try render(RecheckScoreView(snapshot: snapshot, store: store), scheme: scheme, width: 128)
            let count = try accentPixels(bitmap, scheme: scheme)
            XCTAssertGreaterThan(count, 1500, "Ring must show actual 69% progress")
            XCTAssertLessThan(count, 5000, "The accent must not fill the score disk")
            let unknown = try render(RingView(score: nil, size: 128), scheme: scheme, width: 128)
            XCTAssertEqual(try accentPixels(unknown, scheme: scheme), 0, "Unknown scores never imply progress")
        }
    }

    func testEveryDimensionUsesThinTealProgressAndStillFits() throws {
        let dimensions = zip(["routing", "timing", "context", "leverage"], [35, 70, 95, 75]).map {
            Dimension(key: $0, label: $0, score: $1)
        }
        for scheme in [ColorScheme.light, .dark] {
            let bitmap = try render(DimensionBars(dimensions: dimensions, ranking: nil,
                features: ProFeatures(isPro: false), locale: "zh", onSelect: { _ in }), scheme: scheme)
            XCTAssertGreaterThan(try accentPixels(bitmap, scheme: scheme), 600)
            XCTAssertLessThanOrEqual(bitmap.size.height, 220)
        }
    }

    func testMeCopyAndFullPopoverFitInBothLanguagesAndAppearances() async throws {
        for locale in ["zh", "en"] {
            let object: [String: Any] = ["schema": 3, "locale": locale,
                "overall": ["score": 69, "score_version": "1"],
                "usageSummary": ["tokens7D": 32180000],
                "progress_me": ["personal_best": 74, "vs_yesterday": 2, "week_delta": 5],
                "dimensions": zip(["routing", "timing", "context", "leverage"], [35, 70, 95, 75]).map {
                    ["key": $0, "label": $0, "score": $1] as [String: Any]
                }]
            let result = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0)
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            let store = SnapshotStore(defaults: defaults, load: { _, _ in result })
            await store.refresh()?.value
            store.dismissOnboarding()
            for scheme in [ColorScheme.light, .dark] {
                let bitmap = try render(CheckupTab(snapshot: result.snapshot, store: store), scheme: scheme)
                XCTAssertLessThanOrEqual(bitmap.size.height, 600)
                let request = VNRecognizeTextRequest()
                request.usesCPUOnly = true
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    .joined().filter { !$0.isWhitespace }.replacingOccurrences(of: "Almastery", with: "AImastery")
                for expected in locale == "zh" ? ["你的AI掌握度", "全球排名", "能力维度", "满分100", "个人最佳", "加入", "tokens"]
                    : ["YourAImastery", "Globalranking", "Dimensions", "Outof100", "Personalbest", "Join", "tokens"] {
                    XCTAssertTrue(text.localizedCaseInsensitiveContains(expected), text)
                }
                XCTAssertFalse(text.contains("LEVEL"), text)
                let full = try render(PopoverView(store: store).defaultAppStorage(defaults), scheme: scheme, width: 440)
                XCTAssertEqual(full.size.height, 720)
                if let output = ProcessInfo.processInfo.environment["DIRECTION_C_RENDER_OUT"] {
                    try XCTUnwrap(full.representation(using: .png, properties: [:]))
                        .write(to: URL(fileURLWithPath: output + "-\(locale)-\(scheme).png"))
                }
            }
        }
    }
}

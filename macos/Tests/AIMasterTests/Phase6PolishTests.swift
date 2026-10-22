import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class Phase6PolishTests: XCTestCase {
    private func coloredPixels<V: View>(_ view: V, rgb: [Double]) throws -> (count: Int, width: Int) {
        let hosting = NSHostingView(rootView: view.frame(width: 408).bauhausTheme().environment(\.colorScheme, .light))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if zip([color.redComponent, color.greenComponent, color.blueComponent], rgb)
                    .allSatisfy({ abs($0 - $1) < 0.025 }) { count += 1 }
            }
        }
        return (count, bitmap.pixelsWide)
    }

    func testTrialRendersFullWidthAccentButton() throws {
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
            proTrial: ProTrial(read: { nil }, write: { _ in }))
        let pixels = try coloredPixels(ProTrialSection(store: store, zh: true), rgb: [217/255.0, 161/255.0, 46/255.0])
        XCTAssertGreaterThan(pixels.count, pixels.width * 20, "Trial must be a full-width accent button")
    }

    func testJoinUsesNeutralSurfaceBeforeConsent() throws {
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertFalse(store.shareAnonymousScore)
        let pixels = try coloredPixels(GlobalRankCard(store: store, locale: "zh"), rgb: [217/255.0, 161/255.0, 46/255.0])
        XCTAssertEqual(pixels.count, 0, "Joining uses a neutral secondary pill")
    }
    func testPickBenefitsUseOwnTaglineAndRemainDistinctAfterTruncation() {
        let rows = [
            Ranking(name: "a/model", url: "https://example.com/a", tagline: "按任务挑选合适的模型", taskCategory: "model"),
            Ranking(name: "a/agent", url: "https://example.com/b", tagline: "让多个助手协同完成任务", taskCategory: "agent")
        ]
        XCTAssertEqual(DiscoverContent.benefits(rows, locale: "zh"), rows.map(\.tagline))
        let collision = [
            Ranking(name: "a/model", url: "https://example.com/a", tagline: String(repeating: "同", count: 20), taskCategory: "model"),
            Ranking(name: "b/model", url: "https://example.com/b", tagline: String(repeating: "同", count: 20), taskCategory: "model"),
            Ranking(name: "c/model", url: "https://example.com/c", tagline: "", taskCategory: "model"),
            Ranking(name: "d/model", url: "https://example.com/d", tagline: "", taskCategory: "model")
        ]
        for locale in ["zh", "en"] {
            let lines = DiscoverContent.benefits(collision, locale: locale)
            XCTAssertEqual(lines.count, collision.count)
            XCTAssertEqual(Set(lines).count, collision.count)
            XCTAssertFalse(lines.contains(""))
            for line in lines {
                if locale == "zh" {
                    XCTAssertLessThanOrEqual(line.unicodeScalars.filter { (0x3400...0x9fff).contains(Int($0.value)) }.count, 12)
                }
                XCTAssertEqual(ActionCopy.line(line, locale: locale, hanLimit: 12, englishLimit: 29), line)
            }
        }
    }

}

import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class PaletteCTests: XCTestCase {
    private func render<V: View>(_ view: V, scheme: ColorScheme) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.bauhausTheme().environment(\.colorScheme, scheme))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        bitmap.size = hosting.bounds.size
        return bitmap
    }

    private func rgb(_ hex: Int) -> [Double] {
        [Double((hex >> 16) & 255), Double((hex >> 8) & 255), Double(hex & 255)].map { $0 / 255 }
    }

    private func contrast(_ a: Int, _ b: Int) -> Double {
        func luminance(_ hex: Int) -> Double {
            zip(rgb(hex).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) },
                [0.2126, 0.7152, 0.0722]).map(*).reduce(0, +)
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func count(_ hex: Int, in bitmap: NSBitmapImageRep, topRightOnly: Bool = false, tolerance: Double = 0.015) throws -> Int {
        let expected = rgb(hex)
        var count = 0
        let xStart = topRightOnly ? bitmap.pixelsWide * 3 / 4 : 0
        let yEnd = topRightOnly ? Int(60 * Double(bitmap.pixelsHigh) / bitmap.size.height) : bitmap.pixelsHigh
        for y in 0..<yEnd {
            for x in xStart..<bitmap.pixelsWide {
                let pixel = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if zip([pixel.redComponent, pixel.greenComponent, pixel.blueComponent], expected)
                    .allSatisfy({ abs($0 - $1) < tolerance }) { count += 1 }
            }
        }
        return count
    }

    func testWarmTokensAndContrastInBothAppearances() throws {
        // C95A24 gives only 4.224:1 against white. The minimally darker clay is 4.511:1.
        XCTAssertLessThan(contrast(0xFFFFFF, 0xC95A24), 4.5)
        for scheme in [ColorScheme.light, .dark] {
            let dark = scheme == .dark
            let tokens: [(Color, Int, Double)] = [
                (Theme.paper, dark ? 0x1C1916 : 0xF4EEE6, dark ? 0.92 : 0.88),
                (Theme.surface, dark ? 0x2A2521 : 0xFFFFFF, 0.72),
                (Theme.ink, dark ? 0xF2EBE2 : 0x2A211B, 1),
                (Theme.secondary, dark ? 0xBFB3A6 : 0x6E6259, 1),
                (Theme.hairline, dark ? 0xE8D5C2 : 0x5A4636, dark ? 0.17 : 0.15),
                (Theme.accent, dark ? 0xF08A55 : 0xC15723, 1),
                (Theme.accentSurface, dark ? 0xF08A55 : 0xC15723, 0.12),
                (Theme.onAccent, dark ? 0x1C1916 : 0xFFFFFF, 1),
                (Theme.primaryButtonText, dark ? 0x1C1916 : 0xFFFFFF, 1)
            ]
            for (color, hex, alpha) in tokens {
                let bitmap = try render(Rectangle().fill(color).frame(width: 16, height: 16), scheme: scheme)
                let pixel = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
                for (actual, expected) in zip([pixel.redComponent, pixel.greenComponent, pixel.blueComponent], rgb(hex)) {
                    XCTAssertEqual(actual, expected, accuracy: 0.025, "\(scheme) \(String(hex, radix: 16))")
                }
                XCTAssertEqual(pixel.alphaComponent, alpha, accuracy: 0.01)
            }
            let paper = dark ? 0x1C1916 : 0xF4EEE6
            XCTAssertGreaterThanOrEqual(contrast(dark ? 0xF2EBE2 : 0x2A211B, paper), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(dark ? 0xBFB3A6 : 0x6E6259, paper), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(dark ? 0x1C1916 : 0xFFFFFF, dark ? 0xF08A55 : 0xC15723), 4.5)
        }
    }

    func testDimensionsKeepTheirOwnColorsInBarsRingsAndDetailHeaders() throws {
        let keys = ["routing", "timing", "context", "leverage"]
        let dimensions = keys.map { Dimension(key: $0, label: $0, score: 80) }
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for scheme in [ColorScheme.light, .dark] {
            let colors = scheme == .dark ? [0xF08A55, 0x9DBB64, 0x78A6EE, 0xD489C6]
                                        : [0xC95A24, 0x6E8B3D, 0x3A73C9, 0x9A4D8C]
            // A partial/reordered list must preserve each dimension's identity.
            for index in dimensions.indices {
                let dimension = dimensions[index]
                let bar = try render(DimensionBars(dimensions: [dimension], ranking: nil,
                    features: ProFeatures(isPro: false), locale: "en", onSelect: { _ in }).frame(width: 400), scheme: scheme)
                XCTAssertGreaterThan(try count(colors[index], in: bar), 100, dimension.key)
                let ring = try render(DimensionRings(dimensions: [dimension], showsEvidence: false).frame(width: 400), scheme: scheme)
                XCTAssertGreaterThan(try count(colors[index], in: ring), 100, dimension.key)
                let detail = try render(DimensionDetail(dimension: dimension, growth: nil,
                    features: ProFeatures(isPro: false), locale: "en", store: store, back: {}).frame(width: 400), scheme: scheme)
                XCTAssertGreaterThan(try count(colors[index], in: detail), 100, dimension.key)
            }
        }
    }

    func testProEntryHasSolidAccentFillAndOnAccentText() async throws {
        let result = try EngineRunner.decode(Data(#"{"schema":3,"locale":"zh"}"#.utf8), status: 0)
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
        await store.refresh()?.value
        store.dismissOnboarding()
        for scheme in [ColorScheme.light, .dark] {
            let bitmap = try render(PopoverView(store: store), scheme: scheme)
            XCTAssertGreaterThan(try count(scheme == .dark ? 0xF08A55 : 0xC15723, in: bitmap, topRightOnly: true), 500)
            if let output = ProcessInfo.processInfo.environment["TASK65_RENDER_OUT"] {
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: output + "-header-\(scheme).png"))
            }
            XCTAssertGreaterThan(try count(scheme == .dark ? 0x1C1916 : 0xFFFFFF, in: bitmap, topRightOnly: true, tolerance: 0.06), 10)
        }
    }

    func testOverallScoreNumberKeepsAccentColor() throws {
        for scheme in [ColorScheme.light, .dark] {
            let bitmap = try render(RingView(score: 69, size: 128), scheme: scheme)
            let image = try XCTUnwrap(bitmap.cgImage)
            let center = try XCTUnwrap(image.cropping(to: CGRect(x: image.width / 4, y: image.height / 4,
                width: image.width / 2, height: image.height / 2)))
            XCTAssertGreaterThan(try count(scheme == .dark ? 0xF08A55 : 0xC15723,
                in: NSBitmapImageRep(cgImage: center)), 100)
        }
    }

    func testSourcesContainNoOldPaletteHex() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertNil(source.range(of: "(?i)(?:007F75|65DCC6|EDF2F5|242E39|3A4858|1D2933|596773)",
                                      options: .regularExpression), url.lastPathComponent)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }
}

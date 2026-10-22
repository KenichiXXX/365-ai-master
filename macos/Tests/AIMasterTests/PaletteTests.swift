import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class PaletteTests: XCTestCase {
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

    func testGoldTokensAndContrastInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            let dark = scheme == .dark
            let tokens: [(Color, Int, Double)] = [
                (Theme.paper, dark ? 0x12161F : 0xF7F2E8, dark ? 0.92 : 0.88),
                (Theme.surface, dark ? 0x1D2330 : 0xFFFFFF, 0.72),
                (Theme.ink, dark ? 0xEEE8DC : 0x1E1A14, 1),
                (Theme.secondary, dark ? 0xB3AA9C : 0x6B6155, 1),
                (Theme.hairline, dark ? 0xE0D3B8 : 0x5A4A2E, dark ? 0.17 : 0.15),
                (Theme.accent, dark ? 0xF0BE5A : 0xD9A12E, 1),
                (Theme.accentSurface, dark ? 0xF0BE5A : 0xD9A12E, 0.12),
                (Theme.onAccent, dark ? 0x12161F : 0x19150F, 1),
                (Theme.primaryButtonText, dark ? 0x12161F : 0x19150F, 1)
            ]
            for (color, hex, alpha) in tokens {
                let bitmap = try render(Rectangle().fill(color).frame(width: 16, height: 16), scheme: scheme)
                let pixel = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
                for (actual, expected) in zip([pixel.redComponent, pixel.greenComponent, pixel.blueComponent], rgb(hex)) {
                    XCTAssertEqual(actual, expected, accuracy: 0.025, "\(scheme) \(String(hex, radix: 16))")
                }
                XCTAssertEqual(pixel.alphaComponent, alpha, accuracy: 0.01)
            }
            let paper = dark ? 0x12161F : 0xF7F2E8
            XCTAssertGreaterThanOrEqual(contrast(dark ? 0xEEE8DC : 0x1E1A14, paper), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(dark ? 0xB3AA9C : 0x6B6155, paper), 4.5)
            let accentText = dark ? 0xF0BE5A : 0x8A5F0E
            for background in [paper, dark ? 0x1D2330 : 0xFFFFFF] {
                XCTAssertGreaterThanOrEqual(contrast(accentText, background), 4.5)
            }
            XCTAssertGreaterThanOrEqual(contrast(dark ? 0xF0BE5A : 0xD9A12E,
                                               dark ? 0x1D2330 : 0xFFFFFF), 2.3)
            XCTAssertGreaterThanOrEqual(contrast(dark ? 0x12161F : 0x19150F, dark ? 0xF0BE5A : 0xD9A12E), 4.5)
        }
    }

    func testDimensionsKeepTheirOwnColorsInBarsRingsAndDetailHeaders() throws {
        let keys = ["routing", "timing", "context", "leverage"]
        let dimensions = keys.map { Dimension(key: $0, label: $0, score: 80) }
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for scheme in [ColorScheme.light, .dark] {
            let colors = scheme == .dark ? [0xF0BE5A, 0xF08A6A, 0x4FC7B2, 0x8C9BFF]
                                        : [0xD9A12E, 0xC8553A, 0x2E8C7C, 0x5566D6]
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
            XCTAssertGreaterThan(try count(scheme == .dark ? 0xF0BE5A : 0xD9A12E, in: bitmap, topRightOnly: true), 500)
            if let output = ProcessInfo.processInfo.environment["PALETTE_RENDER_OUT"] {
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: output + "-header-\(scheme).png"))
            }
            XCTAssertGreaterThan(try count(scheme == .dark ? 0x12161F : 0x19150F, in: bitmap, topRightOnly: true, tolerance: 0.06), 5)
        }
    }

    func testOverallScoreNumberKeepsAccentColor() throws {
        for scheme in [ColorScheme.light, .dark] {
            let bitmap = try render(RingView(score: 69, size: 128), scheme: scheme)
            let image = try XCTUnwrap(bitmap.cgImage)
            let center = try XCTUnwrap(image.cropping(to: CGRect(x: image.width / 4, y: image.height / 4,
                width: image.width / 2, height: image.height / 2)))
            XCTAssertGreaterThan(try count(scheme == .dark ? 0xF0BE5A : 0xD9A12E,
                in: NSBitmapImageRep(cgImage: center)), 100)
        }
    }

    func testSmallGoldGlyphsAndScoresUseReadableGold() throws {
        for scheme in [ColorScheme.light, .dark] {
            let gold = scheme == .dark ? 0xF0BE5A : 0x8A5F0E
            for background in [Theme.paper, Theme.surface] {
                let trend = try render(TrendMarker(delta: 2).padding(8).background(background), scheme: scheme)
                XCTAssertGreaterThan(try count(gold, in: trend), 3, "\(scheme) trend")
            }
            for size: CGFloat in [64, 96] {
                let bitmap = try render(RingView(score: 69, size: size), scheme: scheme)
                let image = try XCTUnwrap(bitmap.cgImage)
                let center = try XCTUnwrap(image.cropping(to: CGRect(x: image.width / 4, y: image.height / 4,
                    width: image.width / 2, height: image.height / 2)))
                XCTAssertGreaterThan(try count(gold, in: NSBitmapImageRep(cgImage: center)), 10,
                                     "\(scheme) score at \(size)")
            }
        }
    }

    func testSourcesContainNoOldPaletteHex() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertNil(source.range(of: "(?i)(?:A87518|007F75|65DCC6|EDF2F5|242E39|3A4858|1D2933|596773|F4EEE6|1C1916|2A2521|2A211B|F2EBE2|6E6259|BFB3A6|5A4636|E8D5C2|C95A24|C15723|F08A55|6E8B3D|9DBB64|3A73C9|78A6EE|9A4D8C|D489C6)",
                                      options: .regularExpression), url.lastPathComponent)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }
}

import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class ThemeTests: XCTestCase {
    private func components(_ color: Color) throws -> [Double] {
        let rgb = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
    }

    private func contrast(_ foreground: [Double], _ background: [Double]) -> Double {
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return zip(linear, [0.2126, 0.7152, 0.0722]).map(*).reduce(0, +)
        }
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func testWindowUsesNativePopoverMaterial() throws {
        let hosting = NSHostingView(rootView: MasterWindowBackground().frame(width: 440, height: 720))
        hosting.layoutSubtreeIfNeeded()
        func findMaterial(_ view: NSView) -> NSVisualEffectView? {
            if let effect = view as? NSVisualEffectView { return effect }
            return view.subviews.lazy.compactMap { findMaterial($0) }.first
        }
        let material = try XCTUnwrap(findMaterial(hosting))
        XCTAssertEqual(material.material, .popover)
        XCTAssertEqual(material.blendingMode, .behindWindow)
        XCTAssertEqual(material.state, .active)
    }

    func testPaletteAndTextContrastInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            let background = try components(Theme.background(for: scheme))
            let foreground = try components(Theme.foreground(for: scheme))
            let expected = scheme == .light ? [247.0, 242, 232] : [18.0, 22, 31]
            for (actual, byte) in zip(background, expected) { XCTAssertEqual(actual, byte / 255, accuracy: 0.001) }
            XCTAssertGreaterThanOrEqual(contrast(foreground, background), 4.5)
        }
    }

    func testAdaptiveSecondaryActuallyRendersWithAccessibleContrast() throws {
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: ZStack {
                Theme.paper
                Rectangle().fill(Theme.secondary).frame(width: 40, height: 40)
            }.frame(width: 80, height: 80).bauhausTheme().environment(\.colorScheme, scheme))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try pixels.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            func rgb(_ x: Int, _ y: Int) -> [Double] {
                let offset = (y * image.width + x) * 4
                return pixels[offset..<(offset + 3)].map { Double($0) / max(1, Double(pixels[offset + 3])) }
            }
            let background = rgb(1, 1)
            for (actual, expected) in zip(background, try components(Theme.background(for: scheme))) {
                XCTAssertEqual(actual, expected, accuracy: 0.02)
            }
            let foreground = rgb(40, 40)
            XCTAssertGreaterThanOrEqual(contrast(foreground, background), 4.5, "\(scheme): fg=\(foreground), bg=\(background)")
        }
    }

    func testTabBarFitsPopoverForBothLanguagesAndEverySelection() throws {
        for locale in ["zh", "en"] {
            for tab in MasterTab.allCases {
                let hosting = NSHostingView(rootView: MasterTabBar(selection: .constant(tab.rawValue), locale: locale)
                    .bauhausTheme())
                XCTAssertLessThanOrEqual(hosting.fittingSize.width, 408, locale)
                let renderer = ImageRenderer(content: MasterTabBar(selection: .constant(tab.rawValue), locale: locale)
                    .frame(width: 408).bauhausTheme())
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertEqual(image.size.width, 408)
                XCTAssertLessThanOrEqual(image.size.height, 48)
            }
        }
    }

    func testSemanticTabsAndProLabels() {
        XCTAssertEqual(MasterTab.allCases.map { $0.title(locale: "zh") }, ["● 我", "■ 大师推荐", "▲ 修炼"])
        XCTAssertEqual(MasterTab.allCases.map { $0.title(locale: "en") }, ["● Me", "■ Master's picks", "▲ Training"])
        XCTAssertEqual(MasterTab.allCases.map(\.rawValue), [0, 1, 2])
        XCTAssertEqual(Theme.proTitle(isPro: false), "PRO ↗")
        XCTAssertEqual(Theme.proTitle(isPro: true), "PRO ✓")
    }

    func testPopoverHeaderRendersForFreeAndProInBothAppearances() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: fixture)
        for locale in ["zh", "en"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["locale"] = locale
            let result = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0)
            for pro in [false, true] {
                let defaults = UserDefaults(suiteName: UUID().uuidString)!
                var trialData: Data?
                let store = SnapshotStore(defaults: defaults, load: { _, _ in result },
                    proTrial: ProTrial(read: { trialData }, write: { trialData = $0 }))
                await store.refresh()?.value
                store.dismissOnboarding()
                if pro { store.startProTrial() }
                XCTAssertEqual(store.isPro, pro)
                for scheme in [ColorScheme.light, .dark] {
                    let renderer = ImageRenderer(content: PopoverView(store: store).defaultAppStorage(defaults)
                        .environment(\.locale, Locale(identifier: locale)).environment(\.colorScheme, scheme))
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.nsImage)
                    XCTAssertEqual(image.size.width, 440)
                    XCTAssertEqual(image.size.height, 720)
                    if let output = ProcessInfo.processInfo.environment["RENDER_OUT"] {
                        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                            .write(to: URL(fileURLWithPath: output + "-header-\(locale)-\(scheme)-\(pro ? "pro" : "free").png"))
                    }
                }
            }
        }
    }

    func testThemePreservesTranslucentWindowTint() throws {
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: Rectangle().fill(Theme.background(for: scheme)).frame(width: 16, height: 16))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
            try pixels.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 16, height: 16,
                    bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            }
            let alpha = Double(pixels[3]) / 255
            XCTAssertEqual(alpha, scheme == .light ? 0.88 : 0.92, accuracy: 0.01)
            for (actual, expected) in zip(pixels.prefix(3), try components(Theme.background(for: scheme))) {
                XCTAssertEqual(Double(actual) / 255 / alpha, expected, accuracy: 0.01)
            }
        }
    }
}

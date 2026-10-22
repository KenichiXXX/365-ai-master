import XCTest
import SwiftUI
import Vision
@testable import AIMaster

@MainActor
final class DirectionCPicksTests: XCTestCase {
    private func render<V: View>(_ view: V, scheme: ColorScheme) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.frame(width: 400)
            .environment(\.colorScheme, scheme).background(Theme.paper))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        bitmap.size = hosting.bounds.size
        return bitmap
    }

    private func accentArea(_ bitmap: NSBitmapImageRep, scheme: ColorScheme) throws -> Double {
        let expected = scheme == .light ? [0.0, 127, 117] : [101.0, 220, 198]
        var pixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if zip([color.redComponent, color.greenComponent, color.blueComponent], expected)
                    .allSatisfy({ abs($0 - $1 / 255) < 0.03 }) { pixels += 1 }
            }
        }
        return Double(pixels) / pow(Double(bitmap.pixelsWide) / bitmap.size.width, 2)
    }

    func testPrimaryCopyButtonUsesAccentAndDefaultRemainsNeutral() throws {
        for scheme in [ColorScheme.light, .dark] {
            for primary in [false, true] {
                let bitmap = try render(CopyButton(prompt: "Try planning", title: "Copy & try ↗",
                    locale: "en", primary: primary), scheme: scheme)
                let area = try accentArea(bitmap, scheme: scheme)
                if primary { XCTAssertGreaterThan(area, 1500) }
                else { XCTAssertEqual(area, 0) }
            }
        }
    }

    func testReferenceSizedPicksFitWithTagsTwoDigitRanksAndRealGrowth() throws {
        for locale in ["zh", "en"] {
            let names = ["anatomy", "planning", "workflow", "diagram", "research"]
            let rows = (1...5).map { index in
                ["name": "owner/\(names[index - 1])", "url": "https://example.com/\(index)",
                 "tagline": locale == "zh" ? "先写计划，再开始工作" : "Plan before coding",
                 "task_category": index == 1 ? "model" : "context", "stars7d": 8990] as [String: Any]
            }
            let agent: [String: Any] = ["name": "owner/Helper", "url": "https://example.com/agent",
                "tagline": locale == "zh" ? "给重复任务分配助手" : "Delegate repeat tasks", "task_category": "agent"]
            let object: [String: Any] = ["schema": 3, "locale": locale,
                "dimensions": [["key": "routing", "label": "Routing", "score": 35]],
                "book": ["lit": 0, "total": 24, "cards": [], "today": ["id": "plan", "title": locale == "zh" ? "先写计划再动手" : "Plan before coding",
                    "why": locale == "zh" ? "让 AI 先读懂项目" : "Let AI understand the project", "prompt": "Plan first",
                    "level": 1, "lit": false]],
                "rankings": ["origin": "bundled", "skill": rows, "agent": [agent]]]
            let snapshot = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0).snapshot
            let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
            for scheme in [ColorScheme.light, .dark] {
                let bitmap = try render(TodaySkillTab(snapshot: snapshot, store: store), scheme: scheme)
                XCTAssertEqual(bitmap.size.width, 400)
                XCTAssertLessThanOrEqual(bitmap.size.height, 640, "Five reference rows must fit the popover content area")
                let area = try accentArea(bitmap, scheme: scheme)
                XCTAssertGreaterThan(area, 1500, "The primary copy action and square must be teal")
                XCTAssertLessThan(area / (bitmap.size.width * bitmap.size.height), 0.08, "Accent must remain restrained")
                let request = VNRecognizeTextRequest()
                request.usesCPUOnly = true
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US", "zh-Hans"]
                try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                for expected in ["Skill", "Agent", "01", "05", "anatomy", "research", "8,990"] {
                    XCTAssertTrue(text.contains(expected), text)
                }
                XCTAssertFalse(text.contains("PRO"), "No lock when there are no hidden rows")
                if let output = ProcessInfo.processInfo.environment["DIRECTION_C_PICKS_RENDER_OUT"] {
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: URL(fileURLWithPath: output + "-\(locale)-\(scheme).png"))
                }
            }
        }
    }
}

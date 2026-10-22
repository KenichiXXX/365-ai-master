import XCTest
import SwiftUI
import Vision
@testable import AIMaster

@MainActor
extension RenderPreviewTests {
    func phase5Sections(snapshot: Snapshot, store: SnapshotStore) -> [(String, AnyView)] {
        var sections: [(String, AnyView)] = [
            ("checkup", AnyView(CheckupTab(snapshot: snapshot, store: store))),
            ("training", AnyView(TrainingTab(snapshot: snapshot, store: store))),
            ("settings", AnyView(SettingsView(store: store)))
        ]
        if let dimension = snapshot.dimensions?.first {
            sections.append(("dimension-" + dimension.key, AnyView(DimensionDetail(
                dimension: dimension, growth: snapshot.growth, features: store.features,
                locale: snapshot.locale ?? store.locale, store: store, back: {}))))
        }
        sections += DiscoverRanking.allCases.map { ranking in
            ("discover-" + ranking.rawValue,
             AnyView(TodaySkillTab(snapshot: snapshot, store: store, ranking: ranking)))
        }
        return sections
    }

    // Inspect rendered pixels, including dynamic snapshot copy, rather than source strings.
    func phase5VisibleText(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.usesCPUOnly = true
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    func renderPhase5(snapshot: Snapshot, store: SnapshotStore, output: String? = nil,
                      scheme: ColorScheme = .light) throws {
        let locale = snapshot.locale ?? store.locale
        let title = StatusItemController.badgeTitle(snapshot: snapshot)
        let expected = snapshot.overall?.score.map(String.init) ?? "—"
        XCTAssertEqual(title, expected + (snapshot.book?.today?.lit == false ? " •" : ""))
        let sections = phase5Sections(snapshot: snapshot, store: store)
        XCTAssertEqual(sections.count, 8, "All tabs, one detail and four rankings must render")
        for (name, section) in sections {
            let hosting = NSHostingView(rootView: section.padding(name == "settings" ? 0 : 16)
                .frame(width: 440).environment(\.locale, Locale(identifier: locale))
                .environment(\.colorScheme, scheme)
                .background(scheme == .dark ? Color.black : Color.white))
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertEqual(hosting.bounds.width, 440, name)
            XCTAssertGreaterThan(hosting.bounds.height, 100, name)
            if name == "settings" { XCTAssertLessThanOrEqual(hosting.bounds.height, 600) }
            if name == "training" { XCTAssertLessThanOrEqual(hosting.bounds.height, 1100) }
            if name.hasPrefix("discover-"), !store.isPro {
                XCTAssertLessThanOrEqual(hosting.bounds.height, 1500)
            }
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertFalse(png.isEmpty, name)
            if let output { try png.write(to: URL(fileURLWithPath: output + "-" + name + ".png")) }
            if name == "checkup" || name.hasPrefix("discover-") {
                let text = try phase5VisibleText(XCTUnwrap(bitmap.cgImage))
                XCTAssertFalse(text.isEmpty, "OCR must see actual rendered text: \(name)")
                let normalized = text.lowercased().filter { !$0.isWhitespace }
                if name == "checkup" {
                    XCTAssertFalse(normalized.contains("今天先改这一处"), text)
                } else {
                    XCTAssertTrue(normalized.contains(locale == "zh" ? "为你推荐" : "foryou"), text)
                    for word in ["adapter", "schema", "signals", "coverage", "兼容性未知", "API-equivalent"] {
                        XCTAssertFalse(normalized.contains(word.lowercased()), "\(name): \(word)\n\(text)")
                    }
                }
            }
            print("Phase 5 \(name) \(locale) \(store.isPro ? "Pro" : "Free"): \(hosting.bounds.size) pt")
        }
    }

    func testRenderPhase5SyntheticMatrix() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        for locale in ["zh", "en"] {
            for available in [false, true] {
                var object = base
                object["locale"] = locale
                object["overall"] = ["score": available ? 69 as Any : NSNull(),
                                     "availability": available ? "available" : "unavailable"]
                object["dimensions"] = ["routing", "context", "leverage", "timing"].map { key in
                    ["key": key, "label": locale == "zh" ? "模型分工" : "Model choice",
                     "score": available ? 75 as Any : NSNull(),
                     "verdict": locale == "zh" ? "轻量模型用得少" : "Try lighter models more often",
                     "evidence": [["label": locale == "zh" ? "轻量模型占比" : "Light model share", "value": "0%", "target": ">5%"]],
                     "deductions": [["title": "Light model share", "points": 20]],
                     "steps": [locale == "zh" ? "把简单任务交给轻量模型" : "Use a lighter model for simple tasks"],
                     "prompt": "Help me choose a model"] as [String: Any]
                }
                let rows = (1...20).map { index in
                    ["name": "fixture/\(index)", "url": "https://example.com/\(index)",
                     "tagline": locale == "zh" ? "让编程更轻松" : "Make coding easier",
                     "stars": 298000, "stars7d": 9302, "installed": index == 1] as [String: Any]
                }
                object["rankings"] = ["origin": "cached", "skill": rows, "agent": rows, "product": rows]
                object["training_game"] = [
                    "xp": 1170, "level": 7, "level_xp": 120, "next_level_xp": 350,
                    "level_title": locale == "zh" ? "见习" : "Novice",
                    "today": ["checkin": true, "card_read": true, "practice": false, "completed": 2],
                    "shields": 1, "streak": 7, "best_streak": 9, "month": "2026-10", "first_weekday": 3,
                    "calendar": [["date": "2026-10-01", "state": "stamp"], ["date": "2026-10-02", "state": "shield"]],
                    "weekly": ["week": "2026-W43", "kind": "checkins", "title": locale == "zh" ? "打卡 5 天" : "Check in on 5 days",
                               "have": 2, "need": 5, "earned": false], "weekly_badges": []
                ] as [String: Any]
                let result = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0)
                for pro in [false, true] {
                    var trialData: Data?
                    let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                        load: { _, _ in result }, proTrial: ProTrial(read: { trialData }, write: { trialData = $0 }))
                    store.actionCommand = { _ in true }
                    if pro { store.startProTrial() }
                    await store.refresh()?.value
                    store.dismissOnboarding()
                    XCTAssertEqual(store.isPro, pro)
                    for (appearance, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                        let output = ProcessInfo.processInfo.environment["RENDER_OUT"].map {
                            $0 + "-matrix-\(locale)-\(available ? "scored" : "unavailable")-\(pro ? "pro" : "free")-\(appearance)"
                        }
                        try renderPhase5(snapshot: result.snapshot, store: store, output: output, scheme: scheme)
                    }
                }
            }
        }
    }
}

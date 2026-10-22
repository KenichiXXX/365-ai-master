import XCTest
import SwiftUI
import Vision
@testable import AIMaster

@MainActor
extension RenderPreviewTests {
    func testPhase6RenderCoverage() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let snapshot = try EngineRunner.decode(Data(contentsOf: fixture), status: 0).snapshot
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertEqual(Set(phase6Sections(snapshot: snapshot, store: store).map(\.0)),
                       Set(["me", "picks", "training", "dimension", "training-detail", "pro"]))
    }
}

@MainActor
extension RenderPreviewTests {
    func phase6Sections(snapshot: Snapshot, store: SnapshotStore) -> [(String, AnyView)] {
        let locale = snapshot.locale ?? "en"
        var sections = MasterTab.allCases.map { tab -> (String, AnyView) in
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            defaults.set(tab.rawValue, forKey: "selectedTab")
            let name = ["me", "picks", "training"][tab.rawValue]
            return (name, AnyView(PopoverView(store: store).defaultAppStorage(defaults)))
        }
        if let dimension = snapshot.dimensions?.first {
            sections.append(("dimension", AnyView(DimensionDetail(dimension: dimension,
                growth: snapshot.growth, features: store.features, locale: locale, store: store, back: {})
                .padding(16).frame(width: 440))))
        }
        sections.append(("training-detail", AnyView(TrainingDetailPage(destination: .village,
            snapshot: snapshot, store: store).padding(16).frame(width: 440))))
        sections.append(("pro", AnyView(ProSettingsSection(store: store, zh: locale == "zh")
            .padding(16).frame(width: 440))))
        return sections
    }

    private func phase6Text(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.usesCPUOnly = true
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.005
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ").filter { !$0.isWhitespace }
    }

    private func renderPhase6(_ data: Data, output: String?) async throws {
        let result = try EngineRunner.decode(data, status: 0)
        let locale = result.snapshot.locale ?? "en"
        var trialData: Data?
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
            load: { _, _ in result }, proTrial: ProTrial(read: { trialData }, write: { trialData = $0 }))
        store.actionCommand = { _ in true }
        await store.refresh()?.value
        store.dismissOnboarding()
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(MasterTab.allCases.map { String($0.title(locale: locale).prefix(1)) }, ["●", "■", "▲"])
        XCTAssertFalse(MasterTab.allCases.contains { $0.title(locale: locale).contains("体检") })
        let sections = phase6Sections(snapshot: result.snapshot, store: store)
        XCTAssertEqual(sections.count, 6)
        // Full ranking content also checks the locked row below the popover's scroll fold.
        let fullPicks = AnyView(TodaySkillTab(snapshot: result.snapshot, store: store)
            .padding(16).frame(width: 440))
        let hasLockedRows = (result.snapshot.rankings?.skill?.count ?? 0) > 10
        for scheme in [ColorScheme.light, .dark] {
            for (name, section) in sections + [("picks-full", fullPicks)] {
                // AppKit captures ScrollView content that ImageRenderer omits.
                let hosting = NSHostingView(rootView: section.bauhausTheme()
                    .environment(\.locale, Locale(identifier: locale)).environment(\.colorScheme, scheme))
                hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let image = try XCTUnwrap(bitmap.cgImage, name)
                XCTAssertEqual(hosting.bounds.width, 440, name)
                XCTAssertGreaterThan(hosting.bounds.height, 50, name)
                let text = try phase6Text(image)
                XCTAssertFalse(text.isEmpty, name)
                // All page surfaces, including dynamic data, must avoid the retired page label.
                XCTAssertFalse(text.contains("体检"), "\(name): \(text)")
                if ["me", "picks", "training"].contains(name) {
                    XCTAssertEqual(hosting.bounds.height, 720, name)
                    let marker = name == "me" ? (locale == "zh" ? "掌握度" : "mastery") : name == "picks" ? (locale == "zh" ? "今日推荐" : "PICK") : (locale == "zh" ? "今日修炼" : "Today'straining")
                    XCTAssertTrue(text.contains(marker), "Tab content must render, not just its header: \(name): \(text)")
                    XCTAssertTrue(text.contains("PRO"), "Header: \(name): \(text)")
                    for title in locale == "zh" ? ["我", "大师推荐", "修炼"] : ["Me", "Master", "Training"] {
                        XCTAssertTrue(text.contains(title), "Tab bar: \(name): \(text)")
                    }
                }
                if name == "picks-full", hasLockedRows {
                    XCTAssertTrue(text.contains("PRO"), text)
                    XCTAssertTrue(text.contains("11") && text.contains("20"), text)
                    XCTAssertTrue(text.contains(locale == "zh" ? "解锁" : "Unlock"), text)
                }
                // OCR may read the narrow capital I in AI as a lowercase l.
                if name == "pro" {
                    XCTAssertNotNil(text.range(of: "365A[Il]MASTERPRO", options: .regularExpression), text)
                }
                if let output {
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: URL(fileURLWithPath: output + "-\(name)-\(scheme).png"))
                }
                print("Phase 6 \(locale) \(scheme) \(name): \(image.width)x\(image.height)")
            }
        }
    }

    func testRenderPhase6SyntheticMatrix() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        for locale in ["zh", "en"] {
            var object = base
            object["locale"] = locale
            var rankings = try XCTUnwrap(object["rankings"] as? [String: Any])
            let rows = try XCTUnwrap(rankings["skill"] as? [[String: Any]])
            rankings["skill"] = rows + rows.enumerated().map { index, row in
                var copy = row
                copy["name"] = "fixture/locked-\(index)"
                return copy
            }
            object["rankings"] = rankings
            XCTAssertGreaterThan((rankings["skill"] as? [[String: Any]])?.count ?? 0, 10)
            let output = ProcessInfo.processInfo.environment["RENDER_OUT"].map { $0 + "-synthetic-" + locale }
            try await renderPhase6(JSONSerialization.data(withJSONObject: object), output: output)
        }
    }

    // Opt-in: generate snapshots with the checkout's Python engine, never a stale packaged binary.
    // Real snapshots, engine state and PNGs stay in the ignored local render directory.
    func testRenderPhase6RealData() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PHASE6_SNAPSHOT_DIR"],
              let output = ProcessInfo.processInfo.environment["RENDER_OUT"] else {
            throw XCTSkip("set PHASE6_SNAPSHOT_DIR and RENDER_OUT for real-data acceptance")
        }
        for locale in ["zh", "en"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent(locale + ".json"))
            let snapshot = try EngineRunner.decode(data, status: 0).snapshot
            XCTAssertEqual(snapshot.locale, locale)
            XCTAssertNotNil(snapshot.overall?.score, "Real usage must produce a score")
            XCTAssertNotNil(snapshot.trainingGame)
            try await renderPhase6(data, output: output + "-real-" + locale)
        }
    }
}

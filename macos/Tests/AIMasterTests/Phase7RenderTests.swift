import XCTest
import SwiftUI
import Vision
@testable import AIMaster

@MainActor
extension RenderPreviewTests {
    func testPhase7RenderCoverage() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let snapshot = try EngineRunner.decode(Data(contentsOf: fixture), status: 0).snapshot
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertEqual(Set(phase7Sections(snapshot: snapshot, store: store).map(\.0)),
                       Set(["me", "picks", "training", "dimension", "training-detail", "settings", "pro"]))
    }

    private func phase7Sections(snapshot: Snapshot, store: SnapshotStore) -> [(String, AnyView)] {
        let locale = snapshot.locale ?? "en"
        var sections = MasterTab.allCases.map { tab -> (String, AnyView) in
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            defaults.set(tab.rawValue, forKey: "selectedTab")
            return (["me", "picks", "training"][tab.rawValue],
                    AnyView(PopoverView(store: store).defaultAppStorage(defaults)))
        }
        if let dimension = snapshot.dimensions?.first {
            sections.append(("dimension", AnyView(DimensionDetail(dimension: dimension,
                growth: snapshot.growth, features: store.features, locale: locale, store: store, back: {})
                .padding(Theme.pagePadding).frame(width: 440))))
        }
        sections.append(("training-detail", AnyView(TrainingDetailPage(destination: .village,
            snapshot: snapshot, store: store).padding(Theme.pagePadding).frame(width: 440))))
        sections.append(("settings", AnyView(SettingsView(store: store))))
        sections.append(("pro", AnyView(ProSheet(store: store, zh: locale == "zh", close: {}))))
        return sections
    }

    func testPhase7SourcesContainNoBauhausHexValues() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertNil(source.range(of: "(?i)(?:#|0x)(?:D7282F|F2C230|1F4E9E|F4F0E6)",
                                      options: .regularExpression), url.lastPathComponent)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "The guard must actually scan Sources")
    }

    private func phase7Text(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.usesCPUOnly = true
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.005
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined().filter { !$0.isWhitespace }.lowercased()
    }

    private func renderPhase7(_ data: Data, output: String?) async throws {
        let result = try EngineRunner.decode(data, status: 0)
        let snapshot = result.snapshot
        let locale = try XCTUnwrap(snapshot.locale)
        let zh = locale == "zh"
        var trialData: Data?
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
            load: { _, _ in result }, proTrial: ProTrial(read: { trialData }, write: { trialData = $0 }))
        // Captures never execute an app command, start a trial or share data.
        store.actionCommand = { _ in true }
        await store.refresh()?.value
        store.dismissOnboarding()
        let sections = phase7Sections(snapshot: snapshot, store: store)
        XCTAssertEqual(sections.count, 7)
        let dimension = try XCTUnwrap(snapshot.dimensions?.first)
        var markers = [
            "me": zh ? ["掌握度", "全球排名", "能力维度"]
                     : ["mastery", "globalranking", "dimensions"],
            "picks": zh ? ["今日推荐", "skill"] : ["today", "skill"],
            "training": zh ? ["今日修炼"] : ["training"],
            "dimension": [dimension.label.lowercased().filter { !$0.isWhitespace }],
            "training-detail": zh ? ["分享我的练习"] : ["sharemypractice"],
            "settings": zh ? ["设置", "通用", "隐私", "关于"] : ["settings", "general", "privacy", "about"],
            "pro": zh ? ["开始14天免费试用", "输入激活码", "$12", "完成"]
                      : ["start14-dayfreetrial", "enteractivationkey", "$12", "done"]
        ]
        if snapshot.progressMe?.personalBest != nil {
            markers["me"]?.append(zh ? "个人最佳" : "personalbest")
        }
        if !DiscoverContent.picks(snapshot).isEmpty {
            markers["picks"]?.append(zh ? "为你推荐" : "foryou")
        }
        if snapshot.trainingGame != nil {
            markers["training"]?.append(contentsOf: [zh ? "本周挑战" : "weekly", "xp"])
        }
        for scheme in [ColorScheme.light, .dark] {
            for (name, section) in sections {
                let hosting = NSHostingView(rootView: section.bauhausTheme()
                    .background(Theme.paper).environment(\.locale, Locale(identifier: locale))
                    .environment(\.colorScheme, scheme))
                hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                // Attach to an unordered test window so SwiftUI lays out scroll content.
                let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                    backing: .buffered, defer: false)
                window.contentView = hosting
                defer { window.contentView = nil }
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let image = try XCTUnwrap(bitmap.cgImage)
                let context = "\(locale) \(scheme) \(name)"
                XCTAssertEqual(hosting.bounds.width, 440, context)
                XCTAssertGreaterThan(hosting.bounds.height, 50, context)
                var text = try phase7Text(image)
                // Isolate the small footer action so OCR does not merge or omit its glyphs.
                if name == "training-detail" {
                    let footer = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: image.height * 3 / 4,
                        width: image.width, height: image.height - image.height * 3 / 4)))
                    text += try phase7Text(footer)
                }
                // These fixed-height screens scroll. Validate below-fold copy by scrolling
                // the actual view, while preserving the initial viewport PNG below.
                if name == "settings" || (name == "me" && snapshot.progressMe?.personalBest != nil) {
                    func scrollViews(_ view: NSView) -> [NSScrollView] {
                        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
                    }
                    for scroll in scrollViews(hosting) {
                        // SwiftUI owns its scroll offset; its AppKit documentView is empty.
                        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                            wheelCount: 1, wheel1: -1200, wheel2: 0, wheel3: 0))
                        scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: event)))
                    }
                    try await Task.sleep(nanoseconds: 50_000_000)
                    hosting.layoutSubtreeIfNeeded()
                    let scrolled = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                    hosting.cacheDisplay(in: hosting.bounds, to: scrolled)
                    text += try phase7Text(XCTUnwrap(scrolled.cgImage))
                    if let output {
                        try XCTUnwrap(scrolled.representation(using: .png, properties: [:]))
                            .write(to: URL(fileURLWithPath: output + "-\(locale)-\(name)-\(scheme)-scrolled.png"))
                    }
                }
                for marker in try XCTUnwrap(markers[name]) {
                    XCTAssertTrue(text.contains(marker), "\(context): missing \(marker): \(text)")
                }
                if ["me", "picks", "training"].contains(name) {
                    XCTAssertEqual(hosting.bounds.height, 720, context)
                    XCTAssertTrue(text.contains("365"), context)
                    XCTAssertTrue(text.contains("pro"), context)
                    for tab in zh ? ["我", "大师推荐", "修炼"] : ["me", "master", "training"] {
                        XCTAssertTrue(text.contains(tab), "\(context): tab bar: \(text)")
                    }
                }
                if name == "settings" { XCTAssertEqual(hosting.bounds.height, 600, context) }
                if name == "pro" { XCTAssertEqual(hosting.bounds.height, 660, context) }
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertFalse(png.isEmpty, context)
                if let output {
                    try png.write(to: URL(fileURLWithPath: output + "-\(locale)-\(name)-\(scheme).png"))
                }
                print("Phase 7 \(context): \(Int(hosting.bounds.width))x\(Int(hosting.bounds.height)) pt")
            }
        }
        XCTAssertEqual(store.trialStatus, .eligible)
        XCTAssertFalse(store.shareAnonymousScore)
    }

    func testRenderPhase7SyntheticMatrix() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        for locale in ["zh", "en"] {
            var object = base
            object["locale"] = locale
            try await renderPhase7(JSONSerialization.data(withJSONObject: object), output: nil)
        }
    }

    func testRenderTask65WarmPaletteRealData() async throws {
        guard let directory = ProcessInfo.processInfo.environment["TASK65_SNAPSHOT_DIR"],
              let output = ProcessInfo.processInfo.environment["TASK65_RENDER_OUT"] else {
            throw XCTSkip("set TASK65_SNAPSHOT_DIR and TASK65_RENDER_OUT for real-data acceptance")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("zh.json"))
        let snapshot = try EngineRunner.decode(data, status: 0).snapshot
        XCTAssertEqual(snapshot.locale, "zh")
        XCTAssertNotNil(snapshot.overall?.score)
        XCTAssertGreaterThan(snapshot.usageSummary?.tokens7d ?? 0, 0)
        XCTAssertEqual(snapshot.dimensions?.count, 4)
        try await renderPhase7(data, output: output)
    }

    // Real snapshots and PNGs stay in an ignored worktree directory, never in test fixtures.
    // Generate with .venv/bin/python -m agentfit.engine snapshot and an isolated --state-dir.
    func testRenderPhase7RealData() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PHASE7_SNAPSHOT_DIR"],
              let output = ProcessInfo.processInfo.environment["PHASE7_RENDER_OUT"] else {
            throw XCTSkip("set PHASE7_SNAPSHOT_DIR and PHASE7_RENDER_OUT for real-data acceptance")
        }
        for locale in ["zh", "en"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent(locale + ".json"))
            let snapshot = try EngineRunner.decode(data, status: 0).snapshot
            XCTAssertEqual(snapshot.locale, locale)
            XCTAssertNotNil(snapshot.overall?.score, "Real usage must produce a score")
            XCTAssertGreaterThan(snapshot.usageSummary?.tokens7d ?? 0, 0, "Real usage must be present")
            XCTAssertNotNil(snapshot.trainingGame)
            try await renderPhase7(data, output: output)
        }
    }
}

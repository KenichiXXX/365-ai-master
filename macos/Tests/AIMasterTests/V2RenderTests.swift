import XCTest
import SwiftUI
@testable import AIMaster

// Opt-in: scripts/render_v2.sh points these at real local snapshots. PNGs land in build/, never in git.
@MainActor
final class V2RenderTests: XCTestCase {
    private var out: URL!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    func testRenderEveryScreen() async throws {
        for locale in ["zh", "en"] {
            let json = try fixture(locale)
            for scheme in [ColorScheme.light, .dark] {
                let tag = "\(locale)-\(scheme == .dark ? "dark" : "light")"
                let store = try await makeStore(json)
                let snapshot = try XCTUnwrap(store.snapshot)
                try render(PopoverRoot(store: store), name: "01-home-\(tag)", size: popover, scheme: scheme)
                try render(fullHome(store), name: "02-home-full-\(tag)", scheme: scheme)
                for (index, key) in ["routing", "context"].enumerated() {
                    let dimension = try XCTUnwrap(snapshot.dimensions?.first { $0.key == key })
                    try render(page(DimensionPage(dimension: dimension, snapshot: snapshot, store: store, locale: locale, open: { _ in })),
                               name: "1\(index)-dimension-\(key)-\(tag)", scheme: scheme)
                }
                try render(page(PathPage(store: store, locale: locale, open: { _ in })), name: "20-path-\(tag)", scheme: scheme)
                try render(page(DiscoverPage(store: store, locale: locale, open: { _ in })), name: "30-discover-\(tag)", scheme: scheme)
                try render(page(WeeklyPage(store: store, locale: locale, open: { _ in })), name: "40-weekly-free-\(tag)", scheme: scheme)
                try render(page(ProPage(store: store, locale: locale)), name: "50-pro-free-\(tag)", scheme: scheme)
                try render(page(SettingsPage(store: store, locale: locale, open: { _ in })), name: "60-settings-\(tag)", scheme: scheme)
                try render(page(HowItWorksPage(locale: locale)), name: "61-how-\(tag)", scheme: scheme)
                try render(PopoverRoot(store: store, stack: [.path]), name: "21-path-screen-\(tag)", size: popover, scheme: scheme)

                store.startProTrial()
                try render(page(WeeklyPage(store: store, locale: locale, open: { _ in })), name: "41-weekly-pro-\(tag)", scheme: scheme)
                try render(page(ProPage(store: store, locale: locale)), name: "51-pro-trial-\(tag)", scheme: scheme)
                try render(PopoverRoot(store: store), name: "03-home-trial-\(tag)", size: popover, scheme: scheme)

                for (state, edit) in [("waiting", ["evidence_kind": "started"]), ("done", ["lit": true, "evidence_kind": "log_observed"])] {
                    let variant = try await makeStore(try editToday(json, edit))
                    let card = try XCTUnwrap(variant.snapshot?.book?.today)
                    try render(TodayCard(card: card, book: variant.snapshot?.book, store: variant, locale: locale, open: { _ in })
                        .padding(Theme.page).frame(width: Theme.width).background(Theme.canvas).appStyle(),
                               name: "04-today-\(state)-\(tag)", scheme: scheme)
                }

                let fresh = try await makeStore(json, onboarded: false)
                try render(PopoverRoot(store: fresh), name: "00-onboarding-welcome-\(tag)", size: popover, scheme: scheme)
                try render(OnboardingPage(store: fresh, locale: locale, started: true).frame(width: Theme.width, height: Theme.height)
                    .background(Theme.canvas).appStyle(), name: "00-onboarding-reveal-\(tag)", size: popover, scheme: scheme)

                let ranked = try await makeStore(json, ranking: true)
                try render(PopoverRoot(store: ranked), name: "05-home-ranked-\(tag)", size: popover, scheme: scheme)
            }
            let store = try await makeStore(json)
            let snapshot = try XCTUnwrap(store.snapshot)
            let input = try XCTUnwrap(ShareCardInput.from(snapshot, includeScore: true))
            try ShareCardRenderer.png(input, locale: locale).write(to: out.appendingPathComponent("70-share-\(locale).png"))
        }
        for pending in [false, true] {
            let icon = StatusItemController.icon(score: 69, todayPending: pending)
            let view = HStack(spacing: 20) {
                Image(nsImage: icon).renderingMode(.template).foregroundStyle(.black).padding(8).background(Color.white)
                Image(nsImage: icon).renderingMode(.template).foregroundStyle(.white).padding(8).background(Color.black)
            }.scaleEffect(3).frame(width: 520, height: 120)
            try render(view, name: "80-menubar-\(pending ? "pending" : "done")", size: NSSize(width: 520, height: 120), scheme: .light)
        }
    }

    private let popover = NSSize(width: Theme.width, height: Theme.height)

    private func fixture(_ locale: String) throws -> Data {
        let key = "RENDER_SNAPSHOT_\(locale.uppercased())"
        guard let path = ProcessInfo.processInfo.environment[key] else { throw XCTSkip("set \(key)") }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    private func editToday(_ json: Data, _ fields: [String: Any]) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        var book = try XCTUnwrap(object["book"] as? [String: Any])
        var today = try XCTUnwrap(book["today"] as? [String: Any])
        for (key, value) in fields { today[key] = value }
        book["today"] = today
        object["book"] = book
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func makeStore(_ json: Data, onboarded: Bool = true, ranking: Bool = false) async throws -> SnapshotStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(onboarded, forKey: "onboarded")
        defaults.set(false, forKey: "publicDownloads")
        let result = try EngineRunner.decode(json, status: 0)
        var reporter: ScoreReporter?
        if ranking {
            reporter = ScoreReporter(defaults: defaults, transport: { _ in
                (try JSONSerialization.data(withJSONObject: [
                    "total": 1284, "rank": 359, "percentile": 72, "small_sample": false, "score_version": "1",
                    "dims": ["routing": ["rank": 901, "percentile": 30], "timing": ["rank": 512, "percentile": 60],
                             "context": ["rank": 40, "percentile": 97], "leverage": ["rank": 300, "percentile": 77]]]), 200)
            })
        }
        let store = SnapshotStore(defaults: defaults, load: { _, _ in result }, scoreReporter: reporter)
        await store.refresh()?.value
        if ranking { await store.allowScoreSharing() }
        return store
    }

    private func page<V: View>(_ content: V) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 8)
            content.padding(.horizontal, Theme.page).padding(.bottom, Theme.page)
        }
        .frame(width: Theme.width).background(Theme.canvas).appStyle()
    }

    private func fullHome(_ store: SnapshotStore) -> some View {
        VStack(spacing: 0) {
            HomeHeader(store: store, locale: store.snapshot?.locale ?? "en", open: { _ in })
            HomePage(store: store, locale: store.snapshot?.locale ?? "en", open: { _ in })
                .padding(.horizontal, Theme.page).padding(.bottom, Theme.gap)
            HomeFooter(store: store, locale: store.snapshot?.locale ?? "en", open: { _ in })
        }
        .frame(width: Theme.width).background(Theme.canvas).appStyle()
    }

    @discardableResult
    private func render<V: View>(_ view: V, name: String, size: NSSize? = nil, scheme: ColorScheme) throws -> NSSize {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        if let size {
            hosting.frame = NSRect(origin: .zero, size: size)
        } else {
            hosting.frame = NSRect(x: 0, y: 0, width: Theme.width, height: 10)
            hosting.layoutSubtreeIfNeeded()
            hosting.frame = NSRect(origin: .zero, size: NSSize(width: Theme.width, height: hosting.fittingSize.height))
        }
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.bounds.height, 40, name)
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent(name + ".png"))
        return hosting.bounds.size
    }
}

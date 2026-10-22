import XCTest
import SwiftUI
import Vision
@testable import AIMaster

@MainActor
final class DirectionCDetailTests: XCTestCase {
    private func render<V: View>(_ view: V, name: String, locale: String,
                                 scheme: ColorScheme) throws -> NSBitmapImageRep {
        let appearance = try XCTUnwrap(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
        var bitmap: NSBitmapImageRep?
        appearance.performAsCurrentDrawingAppearance {
            let hosting = NSHostingView(rootView: view
                .environment(\.locale, Locale(identifier: locale))
                .environment(\.colorScheme, scheme))
            hosting.appearance = appearance
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
            if let bitmap { hosting.cacheDisplay(in: hosting.bounds, to: bitmap) }
            XCTAssertEqual(hosting.bounds.width, 440, name)
            XCTAssertGreaterThan(hosting.bounds.height, 60, name)
            if name == "settings" { XCTAssertLessThanOrEqual(hosting.bounds.height, 600) }
        }
        let result = try XCTUnwrap(bitmap, name)
        if let output = ProcessInfo.processInfo.environment["TASK60_RENDER_DIR"] {
            let png = try XCTUnwrap(result.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: output)
                .appendingPathComponent("\(name)-\(locale)-\(scheme == .dark ? "dark" : "light").png"))
        }
        return result
    }

    private func text(in bitmap: NSBitmapImageRep) throws -> String {
        let request = VNRecognizeTextRequest()
        request.usesCPUOnly = true
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ").lowercased().filter { !$0.isWhitespace }
    }

    func testDetailSurfacesInBothLanguagesAndAppearances() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        for locale in ["zh", "en"] {
            var object = base
            object["locale"] = locale
            let snapshot = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0).snapshot
            let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
            let dimension = Dimension(key: "routing", label: locale == "zh" ? "模型路由" : "Model routing", score: 75,
                evidence: [RuleEvidence(windowDays: 7, label: "Light model share", value: "0%", target: ">5%")],
                deductions: [ScoreDeduction(title: "Light model share", points: 20)],
                steps: ["Use a lighter model for simple tasks"], prompt: "Help me choose a model")
            let calendar = try JSONDecoder().decode(PracticeCalendarData.self, from: Data(#"{"days":[{"date":"2026-10-19","state":"observed"},{"date":"2026-10-20","state":"self_reported"},{"date":"2026-10-21","state":"usage_only"},{"date":"2026-10-22","state":"unavailable"}],"labels":{"title":"Practice calendar","observed":"Observed","self_reported":"Self-reported","usage_only":"Usage only","unavailable":"Unavailable","rest":"Rest is welcome"}}"#.utf8))
            for scheme in [ColorScheme.light, .dark] {
                for pro in [false, true] {
                    let detail = DimensionDetail(dimension: dimension, growth: snapshot.growth,
                        features: ProFeatures(isPro: pro), locale: locale, store: store, back: {})
                    let bitmap = try render(detail.padding(Theme.pagePadding).frame(width: 440)
                        .background(Theme.paper), name: "dimension-\(pro ? "pro" : "free")", locale: locale, scheme: scheme)
                    XCTAssertTrue(try text(in: bitmap).contains(locale == "zh" ? "模型路由" : "modelrouting"))
                }
                for destination in [TrainingDestination.village, .book, .badges] {
                    _ = try render(TrainingDetailPage(destination: destination, snapshot: snapshot, store: store)
                        .padding(Theme.pagePadding).frame(width: 440).background(Theme.paper),
                        name: destination.rawValue, locale: locale, scheme: scheme)
                }
                let calendarImage = try render(PracticeCalendar(data: calendar)
                    .padding(Theme.pagePadding).frame(width: 440).background(Theme.paper),
                    name: "calendar", locale: locale, scheme: scheme)
                XCTAssertTrue(try text(in: calendarImage).contains("practicecalendar"))
                let settings = try render(SettingsView(store: store), name: "settings", locale: locale, scheme: scheme)
                XCTAssertTrue(try text(in: settings).contains(locale == "zh" ? "设置" : "settings"))
            }
        }
    }

    func testProTrialPrimaryActionAndActivationRemainVisibleAndOffline() throws {
        for locale in ["zh", "en"] {
            for scheme in [ColorScheme.light, .dark] {
                var trialData: Data?
                var now = Date(timeIntervalSince1970: 1_800_000_000)
                let trial = ProTrial(clock: { now }, read: { trialData }, write: { trialData = $0 })
                let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, proTrial: trial)
                XCTAssertEqual(store.trialStatus, .eligible)
                let sheet = ProSheet(store: store, zh: locale == "zh", close: {})
                let eligible = try render(sheet, name: "pro-eligible", locale: locale, scheme: scheme)
                let copy = try text(in: eligible)
                XCTAssertTrue(copy.contains(locale == "zh" ? "开始14天免费试用" : "start14-dayfreetrial"), copy)
                XCTAssertTrue(copy.contains(locale == "zh" ? "输入激活码" : "enteractivationkey"), copy)
                XCTAssertTrue(copy.contains("$12"), copy)
                XCTAssertEqual(store.trialStatus, .eligible, "Rendering never starts the trial")
                XCTAssertNil(store.license)
                store.startProTrial()
                XCTAssertTrue(store.isPro)
                let active = try render(sheet, name: "pro-active", locale: locale, scheme: scheme)
                XCTAssertFalse(try text(in: active).contains(locale == "zh" ? "开始14天免费试用" : "start14-dayfreetrial"))
                now.addTimeInterval(ProTrial.duration)
                store.resumeEntitlement()
                XCTAssertFalse(store.isPro)
                let expired = try render(sheet, name: "pro-expired", locale: locale, scheme: scheme)
                XCTAssertTrue(try text(in: expired).contains(locale == "zh" ? "体验已结束" : "trialended"))
            }
        }
    }
}

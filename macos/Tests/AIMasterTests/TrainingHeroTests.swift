import XCTest
import SwiftUI
import Vision
@testable import AIMaster

@MainActor
final class TrainingHeroTests: XCTestCase {
    func snapshot(locale: String = "en", level: Int = 3, score: Int = 70,
                  earned: Bool = false, passed: Bool = false, checkedIn: Bool = true) throws -> Snapshot {
        let data = Data("""
        {"schema":3,"locale":"\(locale)","overall":{"score":\(score)},
         "growth":{"days":[{"date":"2026-10-21","score":68,"score_version":"v1"}]},
         "village":{"rank_title":"Explorer","quests":[{"key":"q1","title":"First quest","status":"\(passed ? "passed" : "current")"}]},
         "book":{"lit":12,"total":24,"cards":[]},
         "badges":[{"id":"b1","title":"First badge","earned":\(earned)}],
         "training_game":{"xp":120,"level":\(level),"level_xp":20,"next_level_xp":100,"level_title":"Novice",
          "today":{"checkin":\(checkedIn),"card_read":true,"practice":false,"completed":\(checkedIn ? 2 : 1)},
          "shields":1,"streak":12,"best_streak":12,"month":"2026-10","first_weekday":3,
          "calendar":[{"date":"2026-10-22","state":"stamp"}],
          "weekly":{"week":"2026-W43","kind":"checkins","title":"Check in on 5 days","have":3,"need":5,"earned":false},
          "weekly_badges":[]}}
        """.utf8)
        return try EngineRunner.decode(data, status: 0).snapshot
    }

    func text<V: View>(_ view: V, scheme: ColorScheme = .light) throws -> String {
        let renderer = ImageRenderer(content: view.frame(width: 408).bauhausTheme()
            .background(Theme.paper).background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme))
        var observations: [String] = []
        for scale in [2.0, 3.0] {
            renderer.scale = scale
            let request = VNRecognizeTextRequest()
            request.usesCPUOnly = true
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "zh-Hans"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(renderer.cgImage)).perform([request])
            observations += (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
        return observations.joined(separator: "\n")
    }

    func testDirectionCOverviewShowsLiveProgressAndKeepsDetailsReachable() throws {
        let snapshot = try snapshot()
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let view = TrainingTab(snapshot: snapshot, store: store)
        let hosting = NSHostingView(rootView: view.frame(width: 400))
        XCTAssertLessThanOrEqual(hosting.fittingSize.height, 560)
        let visible = try text(view)
        XCTAssertTrue(visible.contains("Today's training"), visible)
        XCTAssertTrue(visible.replacingOccurrences(of: " ", with: "").contains("2/3"), visible)
        XCTAssertTrue(visible.contains("Lv.3"), visible)
        XCTAssertTrue(visible.contains("20 / 100 XP"), visible)
        XCTAssertTrue(visible.contains("12-day streak"), visible)
        XCTAssertTrue(visible.replacingOccurrences(of: " ", with: "").contains("3/5"), visible)
        XCTAssertTrue(visible.contains("Check in on 5 days"), visible)
        XCTAssertTrue(visible.contains("Badges"), visible)
        for detail in ["Check-in calendar", "XP rewards", "Next badge", "Practice history", "Share my practice"] {
            XCTAssertFalse(visible.contains(detail), visible)
        }
    }
    func testAchievementsAreNewOnceAndSurviveRestartAndRollback() throws {
        var ledger = TrainingAchievementLedger()
        let baseline = TrainingAchievementProgress(snapshot: try snapshot())
        XCTAssertTrue(ledger.observe(baseline).isEmpty)
        let reached = TrainingAchievementProgress(snapshot: try snapshot(level: 4, score: 74, earned: true, passed: true))
        let moments = ledger.observe(reached)
        XCTAssertEqual(Set(moments.map(\.id)), ["level:4", "badge:b1", "quest:q1", "best:legacy:74"])
        XCTAssertTrue(moments.contains { $0.title(zh: true) == "新纪录！个人最佳 74" })
        ledger = try JSONDecoder().decode(TrainingAchievementLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertTrue(ledger.observe(reached).isEmpty)
        XCTAssertTrue(ledger.observe(baseline).isEmpty)
        XCTAssertTrue(ledger.observe(reached).isEmpty)
        let empty = try EngineRunner.decode(Data(#"{"schema":3}"#.utf8), status: 0).snapshot
        XCTAssertTrue(ledger.observe(TrainingAchievementProgress(snapshot: empty)).isEmpty)
        XCTAssertTrue(ledger.observe(reached).isEmpty)
    }

    func testNewlyAvailableDataSeedsBaselineAndScoresRespectHistoryAndVersion() throws {
        var ledger = TrainingAchievementLedger()
        let empty = try EngineRunner.decode(Data(#"{"schema":3}"#.utf8), status: 0).snapshot
        XCTAssertTrue(ledger.observe(TrainingAchievementProgress(snapshot: empty)).isEmpty)
        XCTAssertTrue(ledger.observe(TrainingAchievementProgress(snapshot: try snapshot())).isEmpty)
        let historical = try EngineRunner.decode(Data(#"{"schema":3,"overall":{"score":74,"score_version":"v1"},"growth":{"days":[{"date":"2026-10-21","score":80,"score_version":"v1"}]}}"#.utf8), status: 0).snapshot
        XCTAssertTrue(ledger.observe(TrainingAchievementProgress(snapshot: historical)).isEmpty)
        XCTAssertTrue(ledger.observe(TrainingAchievementProgress(snapshot: historical)).isEmpty)
    }

    func testStampRespectsReduceMotion() {
        XCTAssertEqual(TrainingGameView.stampScale(checkedIn: true, reduceMotion: true), 1)
        XCTAssertGreaterThan(TrainingGameView.stampScale(checkedIn: true, reduceMotion: false), 1)
        XCTAssertEqual(TrainingGameView.stampScale(checkedIn: false, reduceMotion: false), 1)
    }

    func testEveryDetailRendersAndHistoryRemainsReachable() throws {
        let snapshot = try snapshot()
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for page in TrainingDestination.allCases {
            let view = TrainingDetailPage(destination: page, snapshot: snapshot, store: store)
            let renderer = ImageRenderer(content: view.frame(width: 408))
            XCTAssertNotNil(renderer.cgImage, page.id)
        }
        let today = try text(TrainingDetailPage(destination: .today, snapshot: snapshot, store: store))
        XCTAssertTrue(today.contains("Check-in calendar"), today)
        XCTAssertTrue(today.contains("XP rewards"), today)
        let challenge = try text(TrainingDetailPage(destination: .challenge, snapshot: snapshot, store: store))
        XCTAssertTrue(challenge.contains("3/5"), challenge)
    }

    func testBothLanguagesAppearancesAndCheckinStatesFit() throws {
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for locale in ["zh", "en"] {
            let snapshot = try snapshot(locale: locale)
            let game = try XCTUnwrap(snapshot.trainingGame)
            for checkedIn in [false, true] {
                let today = DailyGameProgress(checkin: checkedIn, cardRead: false, practice: false,
                                              completed: checkedIn ? 1 : 0, chestTip: nil)
                let changed = TrainingGame(xp: game.xp, level: game.level, levelXp: game.levelXp,
                    nextLevelXp: game.nextLevelXp, levelTitle: game.levelTitle, today: today,
                    shields: game.shields, streak: game.streak, bestStreak: game.bestStreak,
                    month: game.month, firstWeekday: game.firstWeekday, calendar: game.calendar,
                    weekly: game.weekly, weeklyBadges: game.weeklyBadges)
                for scheme in [ColorScheme.light, .dark] {
                    let view = TrainingGameView(game: changed, store: store, zh: locale == "zh")
                        .frame(width: 408).bauhausTheme().environment(\.colorScheme, scheme)
                    XCTAssertNotNil(ImageRenderer(content: view).cgImage)
                    XCTAssertLessThanOrEqual(NSHostingView(rootView: view).fittingSize.height, 300)
                    let visible = try text(view, scheme: scheme)
                    XCTAssertTrue(visible.localizedCaseInsensitiveContains("Lv.3"), visible)
                    XCTAssertTrue(visible.contains("20 / 100 XP"), visible)
                    if locale == "en" {
                        XCTAssertTrue(visible.contains("Today's training"), visible)
                        XCTAssertTrue(visible.contains(checkedIn ? "Checked in" : "Check in +5 XP"), visible)
                    }
                    let tabSnapshot = try self.snapshot(locale: locale, checkedIn: checkedIn)
                    let tab = TrainingTab(snapshot: tabSnapshot, store: store).frame(width: 400)
                        .environment(\.colorScheme, scheme)
                    let rendered = try XCTUnwrap(ImageRenderer(content: tab).cgImage)
                    if let output = ProcessInfo.processInfo.environment["TRAINING_RENDER_DIR"] {
                        let bitmap = NSBitmapImageRep(cgImage: rendered)
                        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        try png.write(to: URL(fileURLWithPath: output)
                            .appendingPathComponent("training-\(locale)-\(scheme)-\(checkedIn).png"))
                    }
                    XCTAssertLessThanOrEqual(NSHostingView(rootView: tab).fittingSize.height, 560)
                }
            }
        }
        let empty = try EngineRunner.decode(Data(#"{"schema":3}"#.utf8), status: 0).snapshot
        XCTAssertNotNil(ImageRenderer(content: TrainingTab(snapshot: empty, store: store).frame(width: 408)).cgImage)
    }

}

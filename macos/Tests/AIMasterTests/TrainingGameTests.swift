import XCTest
import SwiftUI
@testable import AIMaster

@MainActor
final class TrainingGameTests: XCTestCase {
    private func result() throws -> EngineResult {
        let data = Data(#"{"schema":3,"locale":"en","training_game":{"xp":1170,"level":7,"level_xp":120,"next_level_xp":350,"level_title":"Novice","today":{"checkin":true,"card_read":true,"practice":false,"completed":2},"shields":1,"streak":7,"best_streak":9,"month":"2026-10","first_weekday":3,"calendar":[{"date":"2026-10-01","state":"stamp"},{"date":"2026-10-02","state":"shield"}],"weekly":{"week":"2026-W43","kind":"checkins","title":"Check in on 5 days","have":2,"need":5,"earned":false},"weekly_badges":[]}}"#.utf8)
        return try EngineRunner.decode(data, status: 0)
    }

    func testDecodeAndRenderGame() throws {
        let loaded = try result()
        let snapshot = loaded.snapshot
        let game = try XCTUnwrap(snapshot.trainingGame)
        XCTAssertEqual(game.level, 7)
        XCTAssertEqual(game.levelXp, 120)
        XCTAssertEqual(game.today.completed, 2)
        XCTAssertEqual(game.calendar.map(\.state), ["stamp", "shield"])
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SnapshotStore(defaults: defaults, load: { _, _ in loaded })
        let renderer = ImageRenderer(content: TrainingGameView(game: game, store: store, zh: false).padding(16).frame(width: 440))
        XCTAssertEqual(try XCTUnwrap(renderer.nsImage).size.width, 440)
    }

    func testCheckinAndCardReadCommands() async throws {
        let result = try result()
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
        // The command seam verifies exact CLI operations without touching real progress.
        store.actionCommand = { args in
            XCTAssertEqual(args, ["checkin"])
            return true
        }
        await store.checkIn()?.value
        XCTAssertNil(store.lastError)
        store.actionCommand = { args in
            XCTAssertEqual(args, ["mark-card-read", "web_search"])
            return true
        }
        await store.markCardRead("web_search")?.value
        XCTAssertNil(store.lastError)
    }
}

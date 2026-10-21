import XCTest
import AppKit
@testable import AIMaster

@MainActor
final class ProTrialTests: XCTestCase {
    @MainActor private final class Memory {
        var data: Data?
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func trial() -> ProTrial {
            ProTrial(clock: { self.now }, read: { self.data }, write: { self.data = $0 })
        }
    }

    func testEligibleUntilExplicitStartAndIdempotentFourteenDayBoundary() throws {
        let memory = Memory()
        let trial = memory.trial()
        XCTAssertEqual(trial.evaluate(), .eligible)
        XCTAssertNil(memory.data)
        let start = memory.now
        let end = start.addingTimeInterval(14 * 86400)
        XCTAssertEqual(trial.start(), .active(until: end))
        memory.now = start.addingTimeInterval(13 * 86400 + 23 * 3600 + 59 * 60)
        XCTAssertEqual(trial.start(), .active(until: end))
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(memory.data)) as? [String: Any])
        XCTAssertEqual(state["consumed"] as? Bool, true)
        XCTAssertEqual(state["start"] as? Double, start.timeIntervalSince1970)
        XCTAssertEqual(state["end"] as? Double, end.timeIntervalSince1970)
        XCTAssertEqual(state["maximumObserved"] as? Double, memory.now.timeIntervalSince1970)
        XCTAssertEqual(state["expired"] as? Bool, false)
        memory.now = end
        XCTAssertEqual(trial.evaluate(), .expired(.deadline))
        let expired = memory.data
        memory.now = start
        XCTAssertEqual(memory.trial().start(), .expired(.deadline))
        XCTAssertEqual(memory.data, expired)
    }

    func testRestartTimezoneAndRollbackForwardBackAreTerminal() {
        let memory = Memory()
        let start = memory.now
        let end = start.addingTimeInterval(14 * 86400)
        XCTAssertEqual(memory.trial().start(), .active(until: end))
        memory.now += 86400
        XCTAssertEqual(memory.trial().evaluate(), .active(until: end))
        let previous = NSTimeZone.default
        defer { NSTimeZone.default = previous }
        for zone in ["Asia/Tokyo", "America/Los_Angeles", "Pacific/Kiritimati"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            XCTAssertEqual(memory.trial().evaluate(), .active(until: end))
        }
        memory.now -= 1
        XCTAssertEqual(memory.trial().evaluate(), .expired(.clockRollback))
        memory.now = end.addingTimeInterval(1)
        XCTAssertEqual(memory.trial().start(), .expired(.clockRollback))
        memory.now = start
        XCTAssertEqual(memory.trial().evaluate(), .expired(.clockRollback))
        let forward = Memory()
        _ = forward.trial().start()
        forward.now += 15 * 86400
        XCTAssertEqual(forward.trial().evaluate(), .expired(.deadline))
        forward.now -= 15 * 86400
        XCTAssertEqual(forward.trial().start(), .expired(.deadline))
    }

    func testCorruptExistingStateFailsClosedAndCannotRestart() throws {
        let good = Memory()
        _ = good.trial().start()
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(good.data)) as? [String: Any])
        var corrupt = [Data(), Data("{}".utf8), Data("null".utf8)]
        for key in ["consumed", "start", "end", "maximumObserved", "expired"] {
            var missing = state
            missing.removeValue(forKey: key)
            corrupt.append(try JSONSerialization.data(withJSONObject: missing))
        }
        for (key, value) in [("consumed", false as Any), ("end", 0 as Any),
                             ("maximumObserved", 0 as Any), ("expired", "yes" as Any)] {
            var invalid = state
            invalid[key] = value
            corrupt.append(try JSONSerialization.data(withJSONObject: invalid))
        }
        for bytes in corrupt {
            let memory = Memory()
            memory.data = bytes
            XCTAssertEqual(memory.trial().evaluate(), .expired(.corrupt))
            XCTAssertEqual(memory.trial().start(), .expired(.corrupt))
        }
    }

    func testStoreTimerWakeAndRefreshExpireWithoutLosingHistoryOrConsent() async throws {
        let memory = Memory()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let history = Data(#"{"history":{"2026-10-21":{"score":80}},"passed":["first_edit"]}"#.utf8)
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let directory = root.appendingPathComponent(".pytest_cache/trial-history-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let progressFile = directory.appendingPathComponent("progress.json")
        let practiceFile = directory.appendingPathComponent("practice.json")
        try history.write(to: progressFile)
        let practice = Data(#"{"attempts":[{"skill_id":"first_edit","status":"observed"}]}"#.utf8)
        try practice.write(to: practiceFile)
        let notifications = TrialNotificationSpy()
        let store = SnapshotStore(defaults: defaults, weeklyNotifications: notifications, proTrial: memory.trial())
        await store.notificationTask?.value
        store.openWeeklyReview()
        XCTAssertFalse(store.isPro)
        XCTAssertNil(memory.data)
        XCTAssertNil(store.trialExpiryTimer)
        store.startProTrial()
        await store.notificationTask?.value
        XCTAssertTrue(store.isPro)
        guard case .trial(let end) = store.entitlement else { return XCTFail("Expected trial entitlement") }
        XCTAssertEqual(end, memory.now.addingTimeInterval(14 * 86400))
        XCTAssertNotNil(store.trialExpiryTimer)
        XCTAssertEqual(notifications.requests, 0)
        XCTAssertFalse(store.shareAnonymousScore)
        XCTAssertNil(store.publicDownloads)
        store.openWeeklyReview()
        XCTAssertTrue(store.showWeeklyReview)
        let cancellations = notifications.cancellations
        memory.now = end
        store.trialExpiryTimer?.fire()
        await Task.yield()
        XCTAssertFalse(store.isPro)
        XCTAssertFalse(store.showWeeklyReview)
        XCTAssertGreaterThan(notifications.cancellations, cancellations)
        XCTAssertEqual(try Data(contentsOf: progressFile), history)
        XCTAssertEqual(try Data(contentsOf: practiceFile), practice)
        XCTAssertEqual(notifications.requests, 0)
        XCTAssertNil(store.trialExpiryTimer)
        XCTAssertEqual(memory.trial().evaluate(), .expired(.deadline))

        for centerAndName in [(NotificationCenter.default, NSApplication.didBecomeActiveNotification),
                              (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)] {
            let fresh = Memory()
            let resumed = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, proTrial: fresh.trial())
            resumed.startProTrial()
            fresh.now += 14 * 86400
            centerAndName.0.post(name: centerAndName.1, object: nil)
            await Task.yield()
            XCTAssertFalse(resumed.isPro)
            XCTAssertEqual(fresh.trial().evaluate(), .expired(.deadline))
        }
        let fresh = Memory()
        let refreshed = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, proTrial: fresh.trial())
        refreshed.startProTrial()
        fresh.now += 14 * 86400
        refreshed.load = { _, _ in try EngineRunner.decode(Data(#"{"schema":3}"#.utf8), status: 0) }
        await refreshed.refresh()?.value
        XCTAssertFalse(refreshed.isPro)
        XCTAssertFalse(SnapshotStore(defaults: defaults, proTrial: memory.trial()).isPro)
    }
}

@MainActor
private final class TrialNotificationSpy: WeeklyNotificationScheduling {
    var requests = 0
    var cancellations = 0
    func requestPermission() async -> Bool { requests += 1; return true }
    func schedule(context: ReminderContext) async {}
    func cancel() { cancellations += 1 }
}

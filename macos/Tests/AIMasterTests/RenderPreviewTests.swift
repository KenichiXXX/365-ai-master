import XCTest
import SwiftUI
import CryptoKit
@testable import AIMaster

// Opt-in local preview; real usage and generated PNGs must never be committed.
@MainActor
final class RenderPreviewTests: XCTestCase {
    func testRenderLocalValidationAndShareCards() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        let root = URL(fileURLWithPath: out + "-local-fixture")
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let period = try SharePeriod(start: "2026-10-01", end: "2026-10-21")
        for locale in ["zh", "en"] {
            let process = Process()
            process.executableURL = try XCTUnwrap(EngineRunner.engineURL())
            process.arguments = ["snapshot", "--json", "--home", home.path, "--tools", "", "--locale", locale,
                                 "--state-dir", root.appendingPathComponent(locale).path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let result = try EngineRunner.decode(data, status: process.terminationStatus)
            XCTAssertNotNil(result.snapshot.localValidation)
            let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
            await store.refresh()?.value
            let hosting = NSHostingView(rootView: LocalValidationView(snapshot: result.snapshot, store: store)
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: out + "-local-validation-" + locale + ".png"))
            for withScore in [false, true] {
                let card = ShareCardInput(period: period, capabilities: ReviewedCapability.allCases.map {
                    ShareCardInput.Entry(capability: $0, evidence: .reuse)
                }, score: withScore ? try ShareScore(value: 82, coverage: period) : nil)
                let png = try ShareCardRenderer.png(card, locale: locale)
                try png.write(to: URL(fileURLWithPath: out + "-share-" + locale + "-" + String(withScore) + ".png"))
            }
        }
    }

    func testRenderSubscriptionPaywallStatesInBothLanguages() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        let signer = Curve25519.Signing.PrivateKey()
        let clock = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
        func key(exp: String) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: ["v": 1, "lic": "abcdefghijklmnop", "plan": "pro",
                "iat": "2025-10-21", "exp": exp])
            func encode(_ data: Data) -> String {
                data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            }
            return "AIM1.\(encode(data)).\(encode(try signer.signature(for: data)))"
        }
        for locale in ["zh", "en"] {
            for phase in ["paywall", "pending", "offline", "cancel-at-period-end"] {
                let defaults = UserDefaults(suiteName: UUID().uuidString)!
                if phase != "paywall" && phase != "pending" { defaults.set(try key(exp: "2026-10-20"), forKey: "licenseKey") }
                let transport = LicenseServiceTransport { _ in
                    let response: [String: Any] = phase == "cancel-at-period-end"
                        ? ["status": "active", "key": try key(exp: "2027-10-21"), "auto_renew": false,
                           "paid_through": "2027-10-22T00:00:00Z"] : ["status": phase == "pending" ? "pending" : "unavailable"]
                    return (try JSONSerialization.data(withJSONObject: response), phase == "offline" ? 503 : 200)
                }
                let store = SnapshotStore(defaults: defaults, licensePublicKeyBase64: signer.publicKey.rawRepresentation.base64EncodedString(),
                    licenseTransport: transport, licenseClock: { clock })
                await store.licenseRefreshTask?.value
                if phase == "pending" { store.checkoutReturned() }
                else if phase != "paywall" { await store.refreshLicense(explicit: true).value }
                let hosting = NSHostingView(rootView: ProSettingsSection(store: store, zh: locale == "zh")
                    .padding(20).frame(width: 380).environment(\.locale, Locale(identifier: locale))
                    .background(Color(nsColor: .windowBackgroundColor)))
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                hosting.layoutSubtreeIfNeeded()
                XCTAssertEqual(hosting.bounds.width, 380)
                XCTAssertLessThan(hosting.bounds.height, 1500)
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: out + "-subscription-" + phase + "-" + locale + ".png"))
            }
        }
    }

    func testRenderTrialEligibleActiveAndExpiredInBothLanguages() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        for locale in ["zh", "en"] {
            for phase in ["eligible", "active", "expired", "rollback"] {
                var now = Date(timeIntervalSince1970: 1_800_000_000)
                var data: Data?
                let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                    proTrial: ProTrial(clock: { now }, read: { data }, write: { data = $0 }))
                if phase != "eligible" { store.startProTrial() }
                if phase == "expired" { now += 14 * 86400; store.resumeEntitlement() }
                if phase == "rollback" { now -= 1; store.resumeEntitlement() }
                let view = ProSettingsSection(store: store, zh: locale == "zh").padding(20).frame(width: 380)
                    .background(Color(nsColor: .windowBackgroundColor))
                let hosting = NSHostingView(rootView: view)
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                hosting.layoutSubtreeIfNeeded()
                XCTAssertEqual(hosting.bounds.width, 380)
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: out + "-trial-" + phase + "-" + locale + ".png"))
            }
        }
    }

    func testRenderRankingSampleCaptions() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        for locale in ["zh", "en"] {
            for total in [19, 20] {
                let ranking = AppScoreOut(total: total, rank: 2, percentile: total < 20 ? nil : 95, small_sample: total < 20)
                let renderer = ImageRenderer(content: RankingSummary(caption: ranking.caption(locale: locale), ranking: ranking, locale: locale)
                    .padding(16).frame(width: 440).background(Color(nsColor: .windowBackgroundColor)))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: out + "-ranking-\(total)-\(locale).png"))
            }
        }
    }

    func testCompactSettingsFitsOneScreen() throws {
        for locale in ["zh", "en"] {
            for pro in [false, true] {
                var trialData: Data?
                let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                    proTrial: ProTrial(read: { trialData }, write: { trialData = $0 }))
                store.actionCommand = { _ in true }
                if pro { store.startProTrial() }
                XCTAssertEqual(store.isPro, pro)
                let hosting = NSHostingView(rootView: SettingsView(store: store)
                    .environment(\.locale, Locale(identifier: locale))
                    .background(Color(nsColor: .windowBackgroundColor)))
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                hosting.layoutSubtreeIfNeeded()
                XCTAssertEqual(hosting.bounds.width, 440)
                XCTAssertLessThanOrEqual(hosting.bounds.height, 600)
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertFalse(png.isEmpty)
                print("Settings \(locale) \(pro ? "Pro" : "Free"): \(hosting.bounds.width) x \(hosting.bounds.height) pt")
                if let out = ProcessInfo.processInfo.environment["RENDER_OUT"] {
                    try png.write(to: URL(fileURLWithPath: out + "-settings-\(locale)-\(pro ? "pro" : "free").png"))
                }
            }
        }
    }

    func testPhase5RenderCoverageIncludesDetailAndEveryRanking() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let snapshot = try EngineRunner.decode(Data(contentsOf: fixture), status: 0).snapshot
        let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertEqual(Set(phase5Sections(snapshot: snapshot, store: store).map(\.0)),
                       Set(["checkup", "training", "settings", "dimension-routing",
                            "discover-skill", "discover-agent", "discover-learnable", "discover-product"]))
    }

    func testRenderPopoverSections() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        XCTAssertNil(ProcessInfo.processInfo.environment["AIMASTER_PREVIEW_HOME"],
                     "This acceptance check uses real logs; use the synthetic matrix for fixtures")
        for language in ["zh", "en"] {
            let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!) { _, tools in
                let process = Process()
                process.executableURL = try XCTUnwrap(EngineRunner.engineURL())
                let content = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                    .appendingPathComponent("../../../content/daily.json").standardizedFileURL
                process.arguments = EngineRunner.snapshotArguments(locale: language, tools: tools, content: content)
                    + ["--state-dir", out + "-real-state-" + language]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return try EngineRunner.decode(data, status: process.terminationStatus)
            }
            store.actionCommand = { _ in true }
            await store.refresh()?.value
            let snap = try XCTUnwrap(store.snapshot, store.lastError ?? "no snapshot")
            XCTAssertEqual(snap.schema, 3, "Rebuild dist/365engine before rendering")
            XCTAssertNotNil(snap.trainingGame, "The bundled engine must include Phase 5")
            XCTAssertEqual(snap.book?.groups?.map(\.total), [8, 10, 6])
            store.dismissOnboarding()
            try renderPhase5(snapshot: snap, store: store, output: out + "-real-" + language)
            let popover = ImageRenderer(content: PopoverView(store: store))
            popover.scale = 2
            let image = try XCTUnwrap(popover.nsImage)
            XCTAssertEqual(image.size.width, 440)
            XCTAssertLessThanOrEqual(image.size.height, 720)
        }
    }

    func testRenderActionCoverageStates() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        let root = URL(fileURLWithPath: out + "-fixtures-" + UUID().uuidString).standardizedFileURL
        let timestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        for state in ["empty", "partial", "evaluable"] {
            let home = root.appendingPathComponent(state)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            if state != "empty" {
                let relative = state == "partial" ? ".claude/projects/demo/a.jsonl" : ".codex/sessions/a.jsonl"
                let log = home.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
                let lines = state == "partial" ? [
                    #"{"type":"user","uuid":"u1","timestamp":"TIME","message":{"content":"synthetic task"}}"#,
                    #"{"type":"assistant","timestamp":"TIME","message":{"id":"a1","model":"claude-sonnet-5","content":[],"usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":400}}}"#
                ] : [
                    #"{"type":"turn_context","timestamp":"TIME","payload":{"model":"gpt-6.1-sol"}}"#,
                    #"{"type":"event_msg","timestamp":"TIME","payload":{"type":"task_started"}}"#,
                    #"{"type":"token_usage_record","timestamp":"TIME","payload":{"response_id":"r1","turn_id":"t1","usage":{"input_tokens":500,"cached_input_tokens":400,"output_tokens":20}}}"#
                ]
                try (lines.joined(separator: "\n").replacingOccurrences(of: "TIME", with: timestamp) + "\n")
                    .write(to: log, atomically: true, encoding: .utf8)
            }
            for locale in ["zh", "en"] {
                let isolatedState = root.appendingPathComponent("state-" + state + "-" + locale)
                let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!) { _, _ in
                    let process = Process()
                    process.executableURL = try XCTUnwrap(EngineRunner.engineURL())
                    process.arguments = ["snapshot", "--json", "--locale", locale,
                                         "--home", home.path, "--state-dir", isolatedState.path]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    return try EngineRunner.decode(data, status: process.terminationStatus)
                }
                store.dismissOnboarding()
                await store.refresh()?.value
                let snapshot = try XCTUnwrap(store.snapshot, store.lastError ?? "no snapshot")
                XCTAssertEqual(snapshot.overall?.availability,
                               ["empty": "unavailable", "partial": "partial", "evaluable": "available"][state])
                XCTAssertEqual(snapshot.hasEvaluableScores, state == "evaluable")
                let renderer = ImageRenderer(content: CheckupTab(snapshot: snapshot, store: store)
                    .padding(16).frame(width: 440).environment(\.locale, Locale(identifier: locale))
                    .background(Color(nsColor: .windowBackgroundColor)))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertEqual(image.size.width, 440)
                let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: out + "-" + state + "-" + locale + ".png"))
                if state == "empty", locale == "en" {
                    let id = try XCTUnwrap(snapshot.todayTip?.actionId)
                    XCTAssertTrue(try EngineRunner.actionCommand(["action-feedback", id, "not_suitable",
                        "--reason", "no_project", "--state-dir", isolatedState.path]))
                    await store.refresh()?.value
                    let alternative = try XCTUnwrap(store.snapshot?.todayTip?.actionId)
                    XCTAssertNotEqual(alternative, id)
                    XCTAssertEqual(store.snapshot?.todayTip?.source.kind, "pool")
                    await store.refresh()?.value
                    XCTAssertEqual(store.snapshot?.todayTip?.actionId, alternative)
                    XCTAssertTrue(try EngineRunner.actionCommand(["reset-action-preferences", "--state-dir", isolatedState.path]))
                }
            }
        }
    }

    func testRenderPracticeEvidenceStates() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures"))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        for locale in ["zh", "en"] {
            for (kind, status) in [("started", "coverage_missing"), ("log_observed", "observed"), ("reuse", "not_yet")] {
                var object = base
                var book = try XCTUnwrap(object["book"] as? [String: Any])
                var card = try XCTUnwrap((book["cards"] as? [[String: Any]])?.first { $0["id"] as? String == "web_search" })
                card["title"] = locale == "zh" ? "练习搜索能力" : "Practise search"
                card["why"] = locale == "zh" ? "在适合的任务中练习，再检查新记录。" : "Practise in a suitable task, then check new records."
                card["prompt"] = locale == "zh" ? "使用搜索能力后检查新记录。" : "Use search, then check new records."
                card["evidence_kind"] = kind
                card["automatic_supported"] = true
                card["mode"] = "new"
                book["today"] = card
                book["yesterday"] = [["attempt_id": "synthetic-1", "skill_id": card["id"]!, "status": status]]
                object["book"] = book
                object["daily_tip"] = ["id": "synthetic_tip", "title": locale == "zh" ? "完成后检查新记录" : "Check new records after practice",
                                       "detail": locale == "zh" ? "日志存在不证明输出正确。" : "A log record does not prove output correctness."]
                object["locale"] = locale
                let result = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0)
                let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
                await store.refresh()?.value
                let renderer = ImageRenderer(content: TodaySkillTab(snapshot: result.snapshot, store: store)
                    .padding(16).frame(width: 440).environment(\.locale, Locale(identifier: locale))
                    .background(Color(nsColor: .windowBackgroundColor)))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: out + "-practice-" + kind + "-" + locale + ".png"))
            }
        }
    }

    func testRenderComparableHistoryAndAccumulatingReview() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        let root = URL(fileURLWithPath: out + "-history-fixture-" + UUID().uuidString)
        let home = root.appendingPathComponent("empty-home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var history: [String: Any] = [:]
        for offset in [6, 5, 3, 2, 1] {
            let day = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -offset, to: Date()))
            history[formatter.string(from: day)] = ["score": 80 - offset * 3, "dims": [:],
                "score_version": offset >= 3 ? "previous-v1" : "1", "rule_version": "1",
                "timezone": "Asia/Tokyo", "price_version": "unreviewed-v1", "coverage": [:]] as [String: Any]
        }
        for locale in ["zh", "en"] {
            let state = root.appendingPathComponent(locale)
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["history": history, "passed": [:], "regress_notified": []] as [String: Any]).write(to: state.appendingPathComponent("progress.json"))
            let process = Process()
            process.executableURL = try XCTUnwrap(EngineRunner.engineURL())
            process.arguments = ["snapshot", "--json", "--home", home.path, "--state-dir", state.path, "--locale", locale]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let snapshot = try EngineRunner.decode(data, status: process.terminationStatus).snapshot
            let growth = try XCTUnwrap(snapshot.growth)
            XCTAssertEqual(growth.days.count, 30)
            XCTAssertEqual(growth.segments.map(\.count), [2, 1, 2])
            XCTAssertNil(growth.comparableDelta)
            XCTAssertTrue(snapshot.weekly!.reportText!.contains(locale == "zh" ? "可比数据积累中" : "Collecting comparable data"))
            try data.write(to: URL(fileURLWithPath: out + "-history-" + locale + ".json"))
            let views: [(String, AnyView)] = [
                ("curve", AnyView(GrowthCurve(growth: growth, zh: locale == "zh"))),
                ("review", AnyView(WeeklyReviewSheet(snapshot: snapshot)))
            ]
            for (name, view) in views {
                let hosting = NSHostingView(rootView: view.padding(16).frame(width: 440)
                    .background(Color(nsColor: .windowBackgroundColor)))
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: out + "-history-" + name + "-" + locale + ".png"))
            }
        }
    }

    func testRenderPracticeCalendarInBothLanguages() throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        for locale in ["zh", "en"] {
            let labels = locale == "zh"
                ? ["title": "实践历", "observed": "日志实践", "self_reported": "自报尝试", "usage_only": "仅有使用记录",
                   "unavailable": "数据不可用", "rest": "休息不会扣除已获成就"]
                : ["title": "Practice calendar", "observed": "Observed practice", "self_reported": "Self-reported attempt",
                   "usage_only": "Usage only", "unavailable": "Data unavailable", "rest": "Rest does not remove earned achievements"]
            let states = ["observed", "self_reported", "usage_only", "unavailable"]
            let days = (1...30).map { PracticeCalendarDay(date: String(format: "2026-10-%02d", $0), state: states[($0 - 1) % 4]) }
            let calendar = PracticeCalendarData(days: days, labels: labels)
            XCTAssertEqual(days[0].accessibilityLabel(labels: labels, locale: locale), DisplayDate.short("2026-10-01", locale: locale) + ", " + labels["observed"]!)
            let renderer = ImageRenderer(content: PracticeCalendar(data: calendar).padding(16).frame(width: 440)
                .background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertLessThan(image.size.height, 360)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: out + "-calendar-" + locale + ".png"))
        }
    }

    func testRenderPublicContentSources() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        for locale in ["zh", "en"] {
            for origin in ["bundled", "cached"] {
                let row: [String: Any] = ["name": "synthetic/skill", "url": "https://github.com/openai/codex",
                    "tagline": locale == "zh" ? "仅用于预览的合成条目" : "Synthetic preview entry",
                    "source_url": "https://github.com/openai/codex", "source_date": "2026-10-21",
                    "source_type": "curated", "installation_hint": true]
                let object: [String: Any] = ["schema": 3, "locale": locale,
                    "rankings": ["origin": origin, "updated_at": "2026-10-21", "skill": [row], "agent": []],
                    "tool_updates": []]
                let result = try EngineRunner.decode(JSONSerialization.data(withJSONObject: object), status: 0)
                let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
                await store.refresh()?.value
                let renderer = ImageRenderer(content: TodaySkillTab(snapshot: result.snapshot, store: store)
                    .padding(16).frame(width: 440).background(Color(nsColor: .windowBackgroundColor)))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertEqual(image.size.width, 440)
                let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: out + "-public-" + origin + "-" + locale + ".png"))
            }
        }
    }

    func testRenderPhase4ThreeTabsAppearance() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_OUT"] else { throw XCTSkip("set RENDER_OUT") }
        let root = URL(fileURLWithPath: out + "-matrix-fixture")
        let home = root.appendingPathComponent("empty-home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        for locale in ["zh", "en"] {
            let process = Process()
            process.executableURL = try XCTUnwrap(EngineRunner.engineURL())
            process.arguments = ["snapshot", "--json", "--home", home.path, "--tools", "", "--locale", locale,
                                 "--state-dir", root.appendingPathComponent(locale).path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let result = try EngineRunner.decode(data, status: process.terminationStatus)
            let store = SnapshotStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, load: { _, _ in result })
            store.actionCommand = { _ in true }
            await store.refresh()?.value
            store.dismissOnboarding()
            try data.write(to: URL(fileURLWithPath: out + "-matrix-" + locale + ".json"))
            let tabs: [(String, AnyView)] = [
                ("checkup", AnyView(CheckupTab(snapshot: result.snapshot, store: store))),
                ("today", AnyView(TodaySkillTab(snapshot: result.snapshot, store: store))),
                ("training", AnyView(TrainingTab(snapshot: result.snapshot, store: store)))
            ]
            for (name, tab) in tabs {
                let full = ImageRenderer(content: tab.padding(16).frame(width: 440)
                    .environment(\.locale, Locale(identifier: locale)))
                let fullImage = try XCTUnwrap(full.nsImage)
                if name == "today" {
                    XCTAssertGreaterThanOrEqual(result.snapshot.rankings?.skill?.count ?? 0, 5)
                    XCTAssertGreaterThanOrEqual(result.snapshot.rankings?.agent?.count ?? 0, 5)
                    XCTAssertLessThanOrEqual(fullImage.size.height, 1500)
                    print("Synthetic Today (\(locale)): \(fullImage.size.height) pt")
                }
                let fullRep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(fullImage.tiffRepresentation)))
                try XCTUnwrap(fullRep.representation(using: .png, properties: [:])).write(to:
                    URL(fileURLWithPath: out + "-matrix-full-" + name + "-" + locale + ".png"))
                for (appearance, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                    let hosting = NSHostingView(rootView: ScrollView { tab.padding(16) }
                        .frame(width: 440, height: 720)
                        .environment(\.locale, Locale(identifier: locale))
                        .environment(\.colorScheme, scheme)
                        .background(scheme == .dark ? Color.black : Color.white))
                    hosting.frame = NSRect(x: 0, y: 0, width: 440, height: 720)
                    hosting.layoutSubtreeIfNeeded()
                    XCTAssertEqual(hosting.bounds.size, NSSize(width: 440, height: 720))
                    let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                        URL(fileURLWithPath: out + "-matrix-" + name + "-" + locale + "-" + appearance + ".png"))
                }
            }
        }
    }

}

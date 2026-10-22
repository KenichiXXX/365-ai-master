import Foundation
import Combine
import AppKit

@MainActor
final class SnapshotStore: ObservableObject {
    @Published private(set) var entitlement: ProEntitlement = .free
    @Published private(set) var trialStatus: ProTrial.Status = .eligible
    var isPro: Bool { entitlement.isPro }
    private let proTrial: ProTrial
    private(set) var trialExpiryTimer: Timer?
    private(set) var licenseExpiryTimer: Timer?
    private var lifecycleObservers: Set<AnyCancellable> = []
    var license: License.Payload? {
        if case .licensed(let payload) = entitlement { return payload }
        return nil
    }
    @Published private(set) var licenseError: License.Failure?
    private let licensePublicKeyBase64: String
    private let licenseRenewal: LicenseRenewal
    private let licenseClock: () -> Date
    private let courseContentURL: URL
    private(set) var licenseRefreshTask: Task<Void, Never>?
    @Published private(set) var renewalState: RenewalState = .idle
    @Published var autoRefreshLicense: Bool {
        didSet {
            defaults.set(autoRefreshLicense, forKey: "autoRefreshLicense")
            if autoRefreshLicense { refreshLicense() }
        }
    }
    @Published var courseSourceCode: String {
        didSet {
            defaults.set(courseSourceCode, forKey: "courseSourceCode")
            includeCourseSource = false
        }
    }
    @Published var includeCourseSource = false
    @Published private(set) var courseCatalogue: [CourseSource] = []
    var courseSource: CourseSource? { CourseSource.match(courseSourceCode, in: courseCatalogue) }
    var courseCard: SkillCard? { snapshot?.book?.cards.first { $0.id == courseSource?.practiceID } }
    var checkoutSource: CourseSource? { includeCourseSource ? courseSource : nil }
    var signedLicense: License.Payload? {
        defaults.string(forKey: "licenseKey").flatMap { try? License.authenticate($0, publicKeyBase64: licensePublicKeyBase64) }
    }
    let purchaseConfiguration = PurchaseConfiguration.unavailable

    func checkoutReturned() {
        renewalState = .pending
        recordLocalEvent(.checkoutReturn)
    }

    private(set) var localEventTask: Task<Void, Never>?

    @discardableResult
    func recordLocalEvent(_ event: LocalEvent, result: LocalEventResult = .ok) -> Task<Void, Never> {
        let previous = localEventTask
        let command = actionCommand
        let task = Task {
            await previous?.value
            do {
                let accepted = try await Task.detached {
                    try command(["local-event", event.rawValue, "--result", result.rawValue])
                }.value
                if !accepted { localEventError = true }
            } catch { localEventError = true }
        }
        localEventTask = task
        return task
    }
    @Published private(set) var localEventError = false

    @discardableResult
    func refreshLicense(explicit: Bool = false) -> Task<Void, Never> {
        if let licenseRefreshTask { return licenseRefreshTask }
        guard signedLicense != nil else { return Task {} }
        let task = Task { [weak self] in
            guard let self else { return }
            renewalState = .refreshing
            await licenseRenewal.refresh(explicit: explicit)
            renewalState = licenseRenewal.state
            let metricResult: LocalEventResult?
            switch renewalState {
            case .active: metricResult = .active
            case .expired: metricResult = .expired
            case .pending: metricResult = .pending
            case .revoked: metricResult = .revoked
            case .unavailable: metricResult = .unavailable
            default: metricResult = nil
            }
            if let metricResult { recordLocalEvent(.renewal, result: metricResult) }
            revalidateEntitlement()
            licenseRefreshTask = nil
        }
        licenseRefreshTask = task
        return task
    }

    private let weeklyNotifications: WeeklyNotificationScheduling?
    private(set) var notificationTask: Task<Void, Never>?
    @Published var showWeeklyReview = false
    @Published var reminderCard: SkillCard?
    @Published var showProSettings = false
    var features: ProFeatures { ProFeatures(isPro: isPro, coursePracticeID: courseSource?.practiceID) }

    func openWeeklyReview() {
        revalidateEntitlement()
        if features.weeklyReview { showWeeklyReview = true }
    }

    private func updateWeeklyNotifications(requestPermission: Bool = false) {
        revalidateEntitlement()
        guard let weeklyNotifications else { return }
        if remindersPaused || (!dailyPracticeReminders && !(notificationsEnabled && features.weeklyReview)) {
            weeklyNotifications.cancel()
        }
        let previous = notificationTask
        notificationTask = Task {
            await previous?.value
            revalidateEntitlement()
            guard dailyPracticeReminders || (notificationsEnabled && features.weeklyReview) else {
                weeklyNotifications.cancel()
                return
            }
            if requestPermission, !defaults.bool(forKey: "reminderPermissionRequested") {
                defaults.set(true, forKey: "reminderPermissionRequested")
                guard await weeklyNotifications.requestPermission() else { weeklyNotifications.cancel(); return }
            }
            guard !remindersPaused else { weeklyNotifications.cancel(); return }
            await weeklyNotifications.schedule(context: ReminderContext(snapshot: snapshot,
                daily: dailyPracticeReminders, weekly: notificationsEnabled, reviewEntitled: features.weeklyReview,
                paused: remindersPaused, hour: reminderHour, minute: 0, locale: locale))
        }
    }

    @discardableResult
    func openReminder(_ route: [AnyHashable: Any]) -> Bool {
        revalidateEntitlement()
        if let id = route["daily_id"] as? String, WeeklyNotifications.safeID(id),
           let day = route["daily_date"] as? String, day == snapshot?.book?.practiceCalendar?.days.last?.date,
           let card = snapshot?.book?.today, card.id == id {
            reminderCard = card
            return true
        }
        if features.weeklyReview, let id = route["review_id"] as? String,
           id == snapshot?.weekly?.weekStart, snapshot?.weekly?.hasReminderContent == true {
            showWeeklyReview = true
            return true
        }
        return false
    }

    @discardableResult
    func activateLicense(_ key: String) -> Bool {
        do {
            _ = try License.authenticate(key.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   publicKeyBase64: licensePublicKeyBase64)
            defaults.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "licenseKey")
            defaults.set(false, forKey: "manualLicense")
            licenseRenewal.importedKey()
            recordLocalEvent(.activation, result: .importedVerified)
            renewalState = .idle
            licenseError = nil
            updateWeeklyNotifications()
            refreshLicense()
            return true
        } catch {
            licenseError = error as? License.Failure ?? .format
            return false
        }
    }

    @discardableResult
    func handleActivationURL(_ url: URL) -> Bool {
        guard url.scheme == "aimaster365", url.host == "activate",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let key = components.queryItems?.first(where: { $0.name == "key" })?.value else { return false }
        return activateLicense(key)
    }

    private func revalidateEntitlement() {
        let license = defaults.string(forKey: "licenseKey").flatMap {
            try? License.verify($0, publicKeyBase64: licensePublicKeyBase64, today: License.day(licenseClock()))
        }
        let wasPro = isPro
        trialStatus = proTrial.evaluate()
        if let license { entitlement = .licensed(license) }
        else if case .active(let end) = trialStatus { entitlement = .trial(until: end) }
        else { entitlement = .free }
        if renewalState == .idle, let proof = signedLicense, proof.exp < License.day(licenseClock()) {
            renewalState = .expired
        }
        scheduleTrialExpiry()
        scheduleLicenseExpiry()
        if !isPro {
            showWeeklyReview = false
            if wasPro {
                if dailyPracticeReminders { updateWeeklyNotifications() }
                else { weeklyNotifications?.cancel() }
            }
        }
    }

    func startProTrial() {
        guard license == nil else { return }
        let wasEligible = proTrial.evaluate() == .eligible
        let status = proTrial.start()
        if wasEligible, case .active = status { recordLocalEvent(.trialStart) }
        updateWeeklyNotifications()
    }

    func resumeEntitlement() {
        updateWeeklyNotifications()
        refreshLicense()
    }

    private func scheduleLicenseExpiry() {
        licenseExpiryTimer?.invalidate()
        licenseExpiryTimer = nil
        guard let license else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: license.exp),
              let end = formatter.calendar.date(byAdding: .day, value: 1, to: day) else { return }
        let timer = Timer(timeInterval: max(0.001, end.timeIntervalSince(licenseClock())), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resumeEntitlement() }
        }
        RunLoop.main.add(timer, forMode: .common)
        licenseExpiryTimer = timer
    }

    private func scheduleTrialExpiry() {
        trialExpiryTimer?.invalidate()
        trialExpiryTimer = nil
        guard case .active(let end) = trialStatus else { return }
        let timer = Timer(timeInterval: max(0.001, end.timeIntervalSince(proTrial.clock())), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resumeEntitlement() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trialExpiryTimer = timer
    }

    @Published var shareAnonymousScore: Bool {
        didSet {
            defaults.set(shareAnonymousScore, forKey: "shareAnonymousScore")
            if shareAnonymousScore {
                scoreReporter.deviceToken()
                if !oldValue {
                    rankingTask = Task { await refreshRanking(allowFirstReport: true) }
                }
            } else { reportedScore = nil }
        }
    }
    @Published private var reportedScore: AppScoreOut?
    private let scoreReporter: ScoreReporter
    private var rankingTask: Task<Void, Never>?
    @Published private(set) var rankingUnavailable = false

    func allowScoreSharing() async {
        if !shareAnonymousScore { shareAnonymousScore = true }
        await rankingTask?.value
    }

    func rankingCaption(locale: String) -> String {
        guard snapshot?.hasEvaluableScores == true else {
            return NSLocalizedString("No assessable records yet", bundle: .module, comment: "")
        }
        if let ranking { return ranking.caption(locale: locale) }
        if snapshot?.overall?.scoreVersion.map { scoreReporter.hasVersionMismatch(scoreVersion: $0) } ?? true {
            return locale == "zh" ? "评分版本不同，暂不比较" : "Scoring versions differ; comparison unavailable"
        }
        if rankingUnavailable {
            return locale == "zh" ? "暂时连不上排名服务" : "Ranking service unavailable"
        }
        return locale == "zh" ? "正在获取排名…" : "Fetching your ranking…"
    }
    var ranking: AppScoreOut? {
        guard snapshot?.hasEvaluableScores == true, shareAnonymousScore,
              let version = snapshot?.overall?.scoreVersion,
              scoreReporter.cached(scoreVersion: version) != nil,
              reportedScore?.score_version == version else { return nil }
        return reportedScore
    }

    private func refreshRanking(allowFirstReport: Bool = false) async {
        guard shareAnonymousScore, snapshot?.hasEvaluableScores == true,
              let score = snapshot?.overall?.score, let dimensions = snapshot?.dimensions,
              let scoreVersion = snapshot?.overall?.scoreVersion else {
            reportedScore = nil
            rankingUnavailable = false
            return
        }
        let scores = Dictionary(dimensions.compactMap { d in d.score.map { (d.key, $0) } }, uniquingKeysWith: { first, _ in first })
        guard let routing = scores["routing"], let timing = scores["timing"],
              let context = scores["context"], let leverage = scores["leverage"] else { return }
        rankingUnavailable = false
        let result = await scoreReporter.report(score: score,
            dims: .init(routing: routing, timing: timing, context: context, leverage: leverage),
            appVersion: String((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0").prefix(20)),
            scoreVersion: scoreVersion, allowFirstReport: allowFirstReport)
        reportedScore = shareAnonymousScore ? result : nil
        rankingUnavailable = shareAnonymousScore && result == nil
    }

    enum ActionFeedback: String { case later, notSuitable = "not_suitable", never, completed }
    enum ActionReason: String, CaseIterable { case unclear, unsupportedTool = "unsupported_tool", noProject = "no_project", notNow = "not_now" }
    var actionCommand: @Sendable ([String]) throws -> Bool = { try EngineRunner.actionCommand($0) }

    @discardableResult
    func actionFeedback(_ feedback: ActionFeedback, reason: ActionReason? = nil) -> Task<Void, Never>? {
        guard let id = snapshot?.todayTip?.actionId else { return nil }
        var args = ["action-feedback", id, feedback.rawValue]
        if let reason { args += ["--reason", reason.rawValue] }
        return runActionCommand(args)
    }

    @discardableResult
    func resetActionPreferences() -> Task<Void, Never>? {
        runActionCommand(["reset-action-preferences"])
    }

    @discardableResult
    func checkIn() -> Task<Void, Never>? { runActionCommand(["checkin"]) }

    @discardableResult
    func markCardRead(_ id: String) -> Task<Void, Never>? {
        runActionCommand(["mark-card-read", id])
    }

    private func runActionCommand(_ args: [String]) -> Task<Void, Never>? {
        guard !isRefreshing else { return nil }
        isRefreshing = true
        let command = actionCommand
        return Task {
            do {
                let accepted = try await Task.detached { try command(args) }.value
                guard accepted else { throw EngineError.badJSON }
                isRefreshing = false
                await refresh()?.value
            } catch {
                lastError = NSLocalizedString("Refresh failed", bundle: .module, comment: "")
                isRefreshing = false
            }
        }
    }

    @Published private(set) var practiceFeedbackID: String?
    @Published private(set) var practiceFeedback: String?

    func feedback(for id: String) -> String? {
        practiceFeedbackID == id ? practiceFeedback : nil
    }

    @discardableResult
    func practice(id: String, operation: String) -> Task<Void, Never>? {
        guard !isRefreshing else { return nil }
        practiceFeedbackID = nil
        practiceFeedback = nil
        isRefreshing = true
        let command = actionCommand
        return Task {
            do {
                let accepted = try await Task.detached { try command(["practice", id, operation]) }.value
                guard accepted else { throw EngineError.badJSON }
                isRefreshing = false
                await refresh()?.value
                guard lastError == nil else { return }
                guard ["copy", "start", "self"].contains(operation) else { return }
                practiceFeedbackID = id
                practiceFeedback = snapshot?.book?.cards.first { $0.id == id }?.evidenceKind ?? (operation == "self" ? "self_reported" : "started")
            } catch {
                lastError = NSLocalizedString("Refresh failed", bundle: .module, comment: "")
                isRefreshing = false
            }
        }
    }

    enum TriedFeedback { case notSeen, lit }
    @Published private(set) var triedFeedback: TriedFeedback?
    @Published private(set) var onboarded: Bool
    static let refreshIntervals = [60, 300, 900]
    static let allTools = ["claude_code", "codex", "gemini_cli", "opencode", "qwen_code"]
    static let toolNames = ["claude_code": "Claude Code", "codex": "Codex", "gemini_cli": "Gemini CLI", "opencode": "OpenCode", "qwen_code": "Qwen Code"]
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var snapshotJSON = ""
    @Published private(set) var lastError: String?
    @Published private(set) var lastRun: Date?
    @Published private(set) var isRefreshing = false
    @Published var showSettings = false
    @Published private(set) var recheckScan: RecheckScan?
    @Published private(set) var scoreChange: ScoreChange?
    @Published private(set) var recheckCompletedAt: Date?

    @discardableResult
    func recheck() -> Task<Void, Never>? {
        guard !isRefreshing else { return nil }
        return refresh(showScan: true)
    }
    @Published var enabledTools: [String] {
        didSet { defaults.set(enabledTools, forKey: "enabledTools"); refresh() }
    }
    @Published var refreshSeconds: Int {
        didSet { defaults.set(refreshSeconds, forKey: "refreshSeconds"); startTimer() }
    }
    let locale = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en"
    var load: (@Sendable (String, [String]) throws -> EngineResult)?
    var cancelLoad: @Sendable () -> Void = {}
    private var activeScan: EngineScan?
    var tryCard: @Sendable (String) throws -> Bool
    private let defaults: UserDefaults
    private var timer: Timer?
    private lazy var contentUpdater = ContentUpdater(defaults: defaults)

    @Published private(set) var contentStale = false
    var downloadContent: (() async -> Bool)?

    @discardableResult
    func refreshContent() -> Task<Void, Never> {
        Task {
            guard publicDownloads == true else { return }
            let changed: Bool
            if let downloadContent { changed = await downloadContent() }
            else {
                changed = await contentUpdater.refreshIfNeeded()
                contentStale = contentUpdater.stale
            }
            if changed, publicDownloads == true { refresh() }
        }
    }

    @Published var publicDownloads: Bool? {
        didSet {
            defaults.set(publicDownloads, forKey: "publicDownloads")
            if snapshot != nil, publicDownloads != oldValue { refresh() }
        }
    }
    @Published var dailyPracticeReminders: Bool {
        didSet {
            defaults.set(dailyPracticeReminders, forKey: "dailyPracticeReminders")
            updateWeeklyNotifications(requestPermission: dailyPracticeReminders && !oldValue)
        }
    }
    @Published var remindersPaused: Bool {
        didSet {
            defaults.set(remindersPaused, forKey: "remindersPaused")
            updateWeeklyNotifications()
        }
    }
    @Published var reminderHour: Int {
        didSet {
            defaults.set(reminderHour, forKey: "reminderHour")
            updateWeeklyNotifications()
        }
    }
    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
            updateWeeklyNotifications(requestPermission: notificationsEnabled && !oldValue)
        }
    }
    @Published private(set) var onboardingStep: OnboardingStep
    @Published private(set) var obstacle: PracticeObstacle
    @Published private(set) var practiceStatus: FirstPracticeStatus
    @Published private(set) var firstPracticeBranch: FirstPracticeBranch

    func advanceOnboarding() {
        onboardingStep = .obstacle
        defaults.set(onboardingStep.rawValue, forKey: "onboardingStep")
    }

    func chooseObstacle(_ choice: PracticeObstacle) {
        if choice != obstacle { recordFirstPractice(.ready) }
        obstacle = choice
        defaults.set(choice.rawValue, forKey: "practiceObstacle")
        onboardingStep = .practice
        defaults.set(onboardingStep.rawValue, forKey: "onboardingStep")
    }

    func recordFirstPractice(_ status: FirstPracticeStatus) {
        practiceStatus = status
        defaults.set(status.rawValue, forKey: "firstPracticeStatus")
    }

    func firstPracticePrompt(locale: String) -> String {
        if let practice = snapshot?.firstPractice, snapshot?.locale == locale {
            return obstacle == .noProject ? practice.noProjectPrompt : practice.prompt
        }
        let key = obstacle == .noProject ? "First planning prompt" : "First project prompt"
        let language = locale == "zh" ? "zh-Hans" : "en"
        let bundle = Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    func cancelRefresh() {
        guard let activeScan else { return }
        activeScan.cancel()
        cancelLoad()
    }

    func dismissOnboarding() {
        onboarded = true
        onboardingStep = .done
        defaults.set(OnboardingStep.done.rawValue, forKey: "onboardingStep")
        defaults.set(true, forKey: "onboarded")
    }

    @discardableResult
    func markTried(_ card: SkillCard) -> Task<Void, Never>? {
        guard !isRefreshing else { return nil }
        triedFeedback = nil
        practiceFeedbackID = nil
        practiceFeedback = nil
        isRefreshing = true
        let reporter = tryCard
        return Task {
            do {
                if card.isSelfReport {
                    let accepted = try await Task.detached { try reporter(card.id) }.value
                    guard accepted else { throw EngineError.badJSON }
                }
                isRefreshing = false
                await refresh()?.value
                guard lastError == nil else { return }
                let lit = snapshot?.book?.cards.first(where: { $0.id == card.id })?.lit == true
                triedFeedback = lit ? .lit : .notSeen
                practiceFeedbackID = card.id
                practiceFeedback = snapshot?.book?.cards.first { $0.id == card.id }?.evidenceKind ?? "self_reported"
            } catch {
                lastError = NSLocalizedString("Refresh failed", bundle: .module, comment: "")
                isRefreshing = false
            }
        }
    }

    init(defaults: UserDefaults = .standard,
         load: (@Sendable (String, [String]) throws -> EngineResult)? = nil,
         tryCard: @escaping @Sendable (String) throws -> Bool = { try EngineRunner.markTried(id: $0) },
         scoreReporter: ScoreReporter? = nil,
         licensePublicKeyBase64: String = License.publicKeyBase64,
         weeklyNotifications: WeeklyNotificationScheduling? = nil,
         proTrial: ProTrial? = nil,
         licenseTransport: LicenseTransport? = nil,
         licenseClock: @escaping () -> Date = Date.init,
         courseContentURL: URL = EngineRunner.contentURL) {
        self.courseContentURL = courseContentURL
        self.licenseClock = licenseClock
        self.licenseRenewal = LicenseRenewal(defaults: defaults, transport: licenseTransport ?? LicenseServiceTransport(),
            publicKey: licensePublicKeyBase64, clock: licenseClock)
        autoRefreshLicense = defaults.bool(forKey: "autoRefreshLicense")
        courseSourceCode = defaults.string(forKey: "courseSourceCode") ?? ""
        self.proTrial = proTrial ?? ProTrial(defaults: defaults)
        self.weeklyNotifications = weeklyNotifications
        self.licensePublicKeyBase64 = licensePublicKeyBase64
        self.defaults = defaults
        let reporter = scoreReporter ?? ScoreReporter(defaults: defaults)
        self.scoreReporter = reporter
        shareAnonymousScore = defaults.bool(forKey: "shareAnonymousScore")
        reportedScore = reporter.cached()
        self.load = load
        self.tryCard = tryCard
        onboarded = defaults.bool(forKey: "onboarded")
        onboardingStep = defaults.bool(forKey: "onboarded") ? .done : OnboardingStep(rawValue: defaults.string(forKey: "onboardingStep") ?? "") ?? .sources
        obstacle = PracticeObstacle(rawValue: defaults.string(forKey: "practiceObstacle") ?? "") ?? .skipped
        practiceStatus = FirstPracticeStatus(rawValue: defaults.string(forKey: "firstPracticeStatus") ?? "") ?? .ready
        firstPracticeBranch = FirstPracticeBranch(rawValue: defaults.string(forKey: "firstPracticeBranch") ?? "") ?? .noLogs
        publicDownloads = defaults.object(forKey: "publicDownloads") as? Bool ?? true
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        dailyPracticeReminders = defaults.bool(forKey: "dailyPracticeReminders")
        remindersPaused = defaults.bool(forKey: "remindersPaused")
        let hour = defaults.object(forKey: "reminderHour") as? Int ?? 9
        reminderHour = (9..<21).contains(hour) ? hour : 9
        enabledTools = defaults.stringArray(forKey: "enabledTools") ?? Self.allTools
        let interval = defaults.integer(forKey: "refreshSeconds")
        refreshSeconds = Self.refreshIntervals.contains(interval) ? interval : 300
        revalidateEntitlement()
        updateWeeklyNotifications()
        refreshLicense()
        for (center, name) in [(NotificationCenter.default, NSApplication.didBecomeActiveNotification),
                               (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)] {
            center.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor in self?.resumeEntitlement() }
            }.store(in: &lifecycleObservers)
        }
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    @discardableResult
    func refresh(showScan: Bool = false) -> Task<Void, Never>? {
        revalidateEntitlement()
        guard !isRefreshing else { return nil }
        isRefreshing = true
        let tools = enabledTools
        let language = locale
        let content = publicDownloads == true ? EngineRunner.contentURL : nil
        let loader = load
        let scan = EngineScan()
        let previousScore = snapshot?.overall?.score
        if showScan {
            recheckScan = RecheckScan(lines: RecheckScan.lines(snapshot: snapshot, enabledTools: tools))
            scoreChange = nil
            recheckCompletedAt = nil
        }
        activeScan = scan
        return Task {
            let scanAnimation = Task { @MainActor in
                guard showScan else { return }
                let count = recheckScan?.lines.count ?? 0
                for index in 0..<count {
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    guard !Task.isCancelled, !scan.isCancelled else { return }
                    recheckScan?.completed = index + 1
                }
            }
            defer {
                scanAnimation.cancel()
                if showScan { recheckScan = nil }
            }
            do {
                let result = try await Task.detached {
                    if let loader { return try loader(language, tools) }
                    return try EngineRunner.run(locale: language, tools: tools, scan: scan, content: content)
                }.value
                guard !scan.isCancelled else {
                    activeScan = nil
                    isRefreshing = false
                    return
                }
                if showScan {
                    await scanAnimation.value
                    guard !scan.isCancelled else {
                        activeScan = nil
                        isRefreshing = false
                        return
                    }
                    let completedAt = Date()
                    recheckCompletedAt = completedAt
                    if let previousScore, let score = result.snapshot.overall?.score, score != previousScore {
                        scoreChange = ScoreChange(delta: score - previousScore, date: completedAt)
                    }
                    recheckScan = nil
                }
                snapshot = result.snapshot
                courseCatalogue = EngineRunner.courseSources(practiceIDs: Set(result.snapshot.book?.cards.map(\.id) ?? []), content: courseContentURL)
                firstPracticeBranch = FirstPracticeBranch.from(result.snapshot.coverage)
                defaults.set(firstPracticeBranch.rawValue, forKey: "firstPracticeBranch")
                snapshotJSON = result.json
                lastRun = Date()
                lastError = nil
                updateWeeklyNotifications()
                await refreshRanking()
            } catch {
                if !scan.isCancelled {
                    lastError = NSLocalizedString("Refresh failed", bundle: .module, comment: "")
                }
            }
            activeScan = nil
            isRefreshing = false
            if !scan.isCancelled, tools != enabledTools || (content != nil) != (publicDownloads == true) { refresh() }
        }
    }
}

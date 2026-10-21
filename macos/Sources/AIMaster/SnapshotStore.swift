import Foundation
import Combine

@MainActor
final class SnapshotStore: ObservableObject {
    @Published private(set) var isPro = false
    @Published private(set) var license: License.Payload?
    @Published private(set) var licenseError: License.Failure?
    private let licensePublicKeyBase64: String

    @discardableResult
    func activateLicense(_ key: String) -> Bool {
        do {
            let payload = try License.verify(key.trimmingCharacters(in: .whitespacesAndNewlines),
                                             publicKeyBase64: licensePublicKeyBase64)
            defaults.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "licenseKey")
            license = payload
            isPro = true
            licenseError = nil
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

    private func revalidateLicense() {
        license = defaults.string(forKey: "licenseKey").flatMap {
            try? License.verify($0, publicKeyBase64: licensePublicKeyBase64)
        }
        isPro = license != nil
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
        dismissOnboarding()
        await rankingTask?.value
    }

    func rankingCaption(locale: String) -> String {
        if let ranking { return ranking.caption(locale: locale) }
        if rankingUnavailable {
            return locale == "zh" ? "暂时连不上排名服务" : "Ranking service unavailable"
        }
        return locale == "zh" ? "正在获取排名…" : "Fetching your ranking…"
    }
    var ranking: AppScoreOut? {
        guard shareAnonymousScore, scoreReporter.cached() != nil else { return nil }
        return reportedScore
    }

    private func refreshRanking(allowFirstReport: Bool = false) async {
        guard shareAnonymousScore, let overall = snapshot?.overall,
              let dimensions = snapshot?.dimensions else { return }
        let scores = Dictionary(dimensions.map { ($0.key, $0.score) }, uniquingKeysWith: { first, _ in first })
        guard let routing = scores["routing"], let timing = scores["timing"],
              let context = scores["context"], let leverage = scores["leverage"] else { return }
        rankingUnavailable = false
        let result = await scoreReporter.report(score: overall.score,
            dims: .init(routing: routing, timing: timing, context: context, leverage: leverage),
            appVersion: String((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0").prefix(20)),
            allowFirstReport: allowFirstReport)
        reportedScore = shareAnonymousScore ? result : nil
        rankingUnavailable = shareAnonymousScore && result == nil
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
    @Published var enabledTools: [String] {
        didSet { defaults.set(enabledTools, forKey: "enabledTools"); refresh() }
    }
    @Published var refreshSeconds: Int {
        didSet { defaults.set(refreshSeconds, forKey: "refreshSeconds"); startTimer() }
    }
    let locale = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en"
    var load: @Sendable (String, [String]) throws -> EngineResult
    var tryCard: @Sendable (String) throws -> Bool
    private let defaults: UserDefaults
    private var timer: Timer?
    private lazy var contentUpdater = ContentUpdater(defaults: defaults)

    func refreshContent() {
        Task { if await contentUpdater.refreshIfNeeded() { refresh() } }
    }

    func dismissOnboarding() {
        onboarded = true
        defaults.set(true, forKey: "onboarded")
    }

    @discardableResult
    func markTried(_ card: SkillCard) -> Task<Void, Never>? {
        guard !isRefreshing else { return nil }
        triedFeedback = nil
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
            } catch {
                lastError = NSLocalizedString("Refresh failed", bundle: .module, comment: "")
                isRefreshing = false
            }
        }
    }

    init(defaults: UserDefaults = .standard,
         load: @escaping @Sendable (String, [String]) throws -> EngineResult = { try EngineRunner.run(locale: $0, tools: $1) },
         tryCard: @escaping @Sendable (String) throws -> Bool = { try EngineRunner.markTried(id: $0) },
         scoreReporter: ScoreReporter? = nil,
         licensePublicKeyBase64: String = License.publicKeyBase64) {
        self.licensePublicKeyBase64 = licensePublicKeyBase64
        self.defaults = defaults
        let reporter = scoreReporter ?? ScoreReporter(defaults: defaults)
        self.scoreReporter = reporter
        shareAnonymousScore = defaults.bool(forKey: "shareAnonymousScore")
        reportedScore = reporter.cached()
        self.load = load
        self.tryCard = tryCard
        onboarded = defaults.bool(forKey: "onboarded")
        enabledTools = defaults.stringArray(forKey: "enabledTools") ?? Self.allTools
        let interval = defaults.integer(forKey: "refreshSeconds")
        refreshSeconds = Self.refreshIntervals.contains(interval) ? interval : 300
        revalidateLicense()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    @discardableResult
    func refresh() -> Task<Void, Never>? {
        revalidateLicense()
        guard !isRefreshing else { return nil }
        isRefreshing = true
        let tools = enabledTools
        let language = locale
        let loader = load
        return Task {
            do {
                let result = try await Task.detached { try loader(language, tools) }.value
                snapshot = result.snapshot
                snapshotJSON = result.json
                lastRun = Date()
                lastError = nil
                await refreshRanking()
            } catch {
                lastError = NSLocalizedString("Refresh failed", bundle: .module, comment: "")
            }
            isRefreshing = false
            if tools != enabledTools { refresh() }
        }
    }
}

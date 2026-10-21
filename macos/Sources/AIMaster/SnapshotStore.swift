import Foundation
import Combine

@MainActor
final class SnapshotStore: ObservableObject {
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
         tryCard: @escaping @Sendable (String) throws -> Bool = { try EngineRunner.markTried(id: $0) }) {
        self.defaults = defaults
        self.load = load
        self.tryCard = tryCard
        onboarded = defaults.bool(forKey: "onboarded")
        enabledTools = defaults.stringArray(forKey: "enabledTools") ?? Self.allTools
        let interval = defaults.integer(forKey: "refreshSeconds")
        refreshSeconds = Self.refreshIntervals.contains(interval) ? interval : 300
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    @discardableResult
    func refresh() -> Task<Void, Never>? {
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
            } catch {
                lastError = NSLocalizedString("Refresh failed", bundle: .module, comment: "")
            }
            isRefreshing = false
            if tools != enabledTools { refresh() }
        }
    }
}

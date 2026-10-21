import Foundation
import Combine

@MainActor
final class SnapshotStore: ObservableObject {
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
    private let defaults: UserDefaults
    private var timer: Timer?
    private lazy var contentUpdater = ContentUpdater(defaults: defaults)

    func refreshContent() {
        Task { if await contentUpdater.refreshIfNeeded() { refresh() } }
    }

    func markTried(_ card: SkillCard) {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            do {
                try await Task.detached { try EngineRunner.markTried(id: card.id) }.value
            } catch {
                lastError = NSLocalizedString("Refresh failed", bundle: .module, comment: "")
            }
            isRefreshing = false
            refresh()
        }
    }

    init(defaults: UserDefaults = .standard,
         load: @escaping @Sendable (String, [String]) throws -> EngineResult = { try EngineRunner.run(locale: $0, tools: $1) }) {
        self.defaults = defaults
        self.load = load
        enabledTools = defaults.stringArray(forKey: "enabledTools") ?? Self.allTools
        let interval = defaults.integer(forKey: "refreshSeconds")
        refreshSeconds = [30, 60, 300].contains(interval) ? interval : 60
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

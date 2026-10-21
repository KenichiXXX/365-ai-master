import SwiftUI

enum OnboardingStep: String { case sources, obstacle, practice, done }
enum PracticeObstacle: String, CaseIterable {
    case skipped, noProject, noLogs, unsupportedTool, permissionDenied
    var label: String {
        switch self {
        case .skipped: return "Skip"
        case .noProject: return "I have no project"
        case .noLogs: return "No usage records yet"
        case .unsupportedTool: return "My tool does not support this"
        case .permissionDenied: return "Logs cannot be read. Try again later"
        }
    }
}
enum FirstPracticeStatus: String { case ready, copied, selfReported }
enum FirstPracticeBranch: String {
    case usableLogs, noLogs, unsupported, permissionDenied
    var label: String {
        switch self {
        case .usableLogs: return "Usage records available"
        case .noLogs: return "No usage records yet"
        case .unsupported: return "This log format is not supported yet"
        case .permissionDenied: return "Logs cannot be read. Try again later"
        }
    }
    static func from(_ coverage: [String: SourceCoverage]?) -> Self {
        let sources = Array((coverage ?? [:]).values)
        if sources.contains(where: { $0.validUsageCount > 0 && [.ok, .partial].contains($0.status) }) { return .usableLogs }
        if sources.contains(where: { $0.status == .permissionDenied }) { return .permissionDenied }
        if sources.contains(where: { $0.status == .unsupported }) { return .unsupported }
        return .noLogs
    }
}

struct FirstPracticeView: View {
    @ObservedObject var store: SnapshotStore
    var locale: String? = nil
    private var language: String { locale ?? store.snapshot?.locale ?? store.locale }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try one step", bundle: .module).font(.headline)
            if !store.onboarded && store.onboardingStep == .sources {
                Text("Allowed source explanation", bundle: .module).font(.caption)
                DisclosureGroup {
                    ForEach(SnapshotStore.allTools, id: \.self) { tool in
                        Toggle(SnapshotStore.toolNames[tool] ?? tool, isOn: Binding(
                            get: { store.enabledTools.contains(tool) },
                            set: { on in store.enabledTools = SnapshotStore.allTools.filter {
                                $0 == tool ? on : store.enabledTools.contains($0)
                            } }))
                    }
                } label: { Text("View allowed sources", bundle: .module) }
                OptionalPracticePreferences(store: store)
                Button(action: store.advanceOnboarding) { Text("Continue", bundle: .module) }
            } else if !store.onboarded && store.onboardingStep == .obstacle {
                Text("What is in the way?", bundle: .module)
                ForEach(PracticeObstacle.allCases, id: \.self) { obstacle in
                    Button(action: { store.chooseObstacle(obstacle) }) {
                        Text(LocalizedStringKey(obstacle.label), bundle: .module)
                    }
                }
            } else {
                Text(LocalizedStringKey(store.firstPracticeBranch.label), bundle: .module).font(.caption)
                if store.firstPracticeBranch == .permissionDenied {
                    Text("Retry or practice manually; broad disk access is not required", bundle: .module).font(.caption)
                }
                Text(store.firstPracticePrompt(locale: language)).font(.callout).textSelection(.enabled)
                Text("Practice limitation", bundle: .module).font(.caption).foregroundStyle(.secondary)
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.firstPracticePrompt(locale: language), forType: .string)
                    store.recordFirstPractice(.copied)
                }) { Text("Copy practice", bundle: .module) }
                if store.practiceStatus == .copied {
                    Text("Practice copied; not verified yet", bundle: .module).font(.caption)
                }
                if store.practiceStatus == .selfReported {
                    Text("Tried (self-reported)", bundle: .module).font(.caption)
                }
                Button(action: { store.recordFirstPractice(.selfReported) }) {
                    Text("Tried (self-reported)", bundle: .module)
                }
                Button(action: { store.chooseObstacle(store.obstacle == .noProject ? .skipped : .noProject) }) {
                    Text(store.obstacle == .noProject ? "I have a project" : "I have no project", bundle: .module)
                }
                Button(action: { store.dismissOnboarding(); store.refresh() }) {
                    Text("Return to check-up", bundle: .module)
                }
            }
            if store.isRefreshing {
                ProgressView { Text("Scanning allowed sources", bundle: .module) }
                Button(action: store.cancelRefresh) { Text("Cancel scan", bundle: .module) }
            } else {
                Button(action: { store.refresh() }) { Text("Retry", bundle: .module) }
            }
            if !store.onboarded {
                Button(action: { store.chooseObstacle(.skipped) }) { Text("Practice manually", bundle: .module) }
            }
        }.padding(12).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct OptionalPracticePreferences: View {
    @ObservedObject var store: SnapshotStore
    @State private var rankingConsent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { store.publicDownloads == true }, set: { store.publicDownloads = $0 })) {
                Text("Download public content", bundle: .module)
            }
            Text("Public download explanation", bundle: .module).font(.caption)
            Toggle(isOn: Binding(get: { store.shareAnonymousScore }, set: { on in
                if on { rankingConsent = true } else { store.shareAnonymousScore = false }
            })) { Text("Join ranking", bundle: .module) }
            if rankingConsent {
                ScoreConsentPanel(store: store, zh: store.locale == "zh", close: { rankingConsent = false })
            }
            ReminderSettings(store: store)
        }
    }
}

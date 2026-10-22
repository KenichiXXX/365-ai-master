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
        Group {
            VStack(alignment: .leading, spacing: Theme.grid) {
                Text("Try one step", bundle: .module).font(Theme.title)
                if !store.onboarded && store.onboardingStep == .sources {
                    Text("Allowed source explanation", bundle: .module).font(Theme.label)
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
                    Menu {
                        ForEach(PracticeObstacle.allCases, id: \.self) { obstacle in
                            Button(action: { store.chooseObstacle(obstacle) }) {
                                Text(LocalizedStringKey(obstacle.label), bundle: .module)
                            }
                        }
                    } label: { Text("What is in the way?", bundle: .module) }
                } else {
                    DisclosureGroup {
                        Text(LocalizedStringKey(store.firstPracticeBranch.label), bundle: .module).font(Theme.label)
                        if store.firstPracticeBranch == .permissionDenied {
                            Text("Retry or practice manually; broad disk access is not required", bundle: .module).font(Theme.label)
                        }
                        Text(store.firstPracticePrompt(locale: language)).font(Theme.body).textSelection(.enabled)
                        Text("Practice limitation", bundle: .module).font(Theme.label)
                    } label: { Image(systemName: "info.circle").accessibilityLabel(Text("Practice manually", bundle: .module)) }
                    HStack {
                        CopyButton(prompt: store.firstPracticePrompt(locale: language),
                                   title: language == "zh" ? "复制给 Claude 的指令" : "Copy prompt", locale: language,
                                   onCopied: { store.recordFirstPractice(.copied) })
                        Button(action: { store.dismissOnboarding(); store.refresh() }) { Text("Check now", bundle: .module) }
                            .disabled(store.isRefreshing)
                        Menu {
                            scanOptions
                            Button(action: { store.recordFirstPractice(.selfReported) }) {
                                Text("Tried (self-reported)", bundle: .module)
                            }
                            Button(action: { store.chooseObstacle(store.obstacle == .noProject ? .skipped : .noProject) }) {
                                Text(store.obstacle == .noProject ? "I have a project" : "I have no project", bundle: .module)
                            }
                            Button(action: { store.dismissOnboarding(); store.refresh() }) {
                                Text("Return to check-up", bundle: .module)
                            }
                        } label: { Text("⋯") }
                            .menuStyle(.borderlessButton).fixedSize()
                            .accessibilityLabel(language == "zh" ? "更多操作" : "More actions")
                    }.controlSize(.small)
                    if store.practiceStatus == .copied {
                        Text("Practice copied; not verified yet", bundle: .module).font(Theme.label).foregroundStyle(Theme.secondary)
                    } else if store.practiceStatus == .selfReported {
                        Text("Tried (self-reported)", bundle: .module).font(Theme.label).foregroundStyle(Theme.secondary)
                    }
                }
                if store.isRefreshing {
                    ProgressView { Text("Scanning allowed sources", bundle: .module) }
                }
                if !store.onboarded && store.onboardingStep != .practice && store.onboardingStep != .done {
                    Menu { scanOptions } label: { Text("⋯") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel(language == "zh" ? "更多操作" : "More actions")
                }
            }.padding(Theme.grid * 2).bauhausPanel()
        }.bauhausTheme()
    }

    @ViewBuilder private var scanOptions: some View {
        if store.isRefreshing {
            Button(action: store.cancelRefresh) { Text("Cancel scan", bundle: .module) }
        } else {
            Button(action: { store.refresh() }) { Text("Retry", bundle: .module) }
        }
        if !store.onboarded {
            Button(action: { store.chooseObstacle(.skipped) }) { Text("Practice manually", bundle: .module) }
        }
    }

}

struct OptionalPracticePreferences: View {
    @ObservedObject var store: SnapshotStore
    @State private var rankingConsent = false
    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(get: { store.publicDownloads == true }, set: { store.publicDownloads = $0 })) {
                    Text("Download public content", bundle: .module)
                }
                Text("Public download explanation", bundle: .module).font(Theme.label)
                Toggle(isOn: Binding(get: { store.shareAnonymousScore }, set: { on in
                    if on { rankingConsent = true } else { store.shareAnonymousScore = false }
                })) { Text("Join ranking", bundle: .module) }
                if rankingConsent {
                    ScoreConsentPanel(store: store, zh: store.locale == "zh", close: { rankingConsent = false })
                }
                ReminderSettings(store: store)
            }
        }.bauhausTheme()
    }
}

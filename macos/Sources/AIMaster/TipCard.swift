import SwiftUI

struct TipCard: View {
    let tip: Tip
    @ObservedObject var store: SnapshotStore
    var dimensions: [Dimension] = []
    @Environment(\.locale) private var displayLocale

    private var copyTitle: String {
        let language = displayLocale.identifier.hasPrefix("zh") ? "zh-Hans" : "en"
        let bundle = Bundle.module.url(forResource: language, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
        return bundle.localizedString(forKey: "Copy prompt", value: nil, table: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tip.title).font(.headline)
            Text(tip.why).font(.body).foregroundStyle(.secondary)
            DisclosureGroup {
                if let evidence = tip.evidenceSummary { Text(evidence).font(.callout) }
                if let limitation = tip.limitation { Text(limitation).font(.caption) }
                ForEach(Array(tip.steps.prefix(3).enumerated()), id: \.offset) { index, step in
                    Text(step).font(.callout)
                }
                if !dimensions.isEmpty { DimensionEvidence(dimensions: dimensions) }
                FirstPracticeView(store: store)
            } label: { Image(systemName: "info.circle").accessibilityLabel(Text("Why this suggestion", bundle: .module)) }
            if !tip.promptForClaude.isEmpty {
                HStack {
                    CopyButton(prompt: tip.promptForClaude,
                               title: copyTitle,
                               locale: displayLocale.identifier.hasPrefix("zh") ? "zh" : "en",
                               onCopied: {
                                   if let id = tip.actionId { store.practice(id: id, operation: "copy") }
                               })
                    Button(action: { store.refresh() }) { Text("Check now", bundle: .module) }
                        .disabled(store.isRefreshing)
                    if let id = tip.actionId {
                        Menu {
                            Button(displayLocale.identifier.hasPrefix("zh") ? "开始实践" : "Start practice") {
                                store.practice(id: id, operation: "start")
                            }
                            if tip.validationKind == "self_report" {
                                Button(displayLocale.identifier.hasPrefix("zh") ? "已尝试（自报）" : "Tried (self-reported)") {
                                    store.practice(id: id, operation: "self")
                                }
                            }
                            Button(action: { store.actionFeedback(.later) }) { Text("Later", bundle: .module) }
                            Menu {
                                ForEach(SnapshotStore.ActionReason.allCases, id: \.self) { reason in
                                    Button(action: { store.actionFeedback(.notSuitable, reason: reason) }) {
                                        Text(LocalizedStringKey(reason.label), bundle: .module)
                                    }
                                }
                            } label: { Text("Not suitable", bundle: .module) }
                            Button(action: { store.actionFeedback(.never) }) { Text("Do not suggest again", bundle: .module) }
                        } label: { Text("⋯") }
                            .menuStyle(.borderlessButton).fixedSize()
                            .accessibilityLabel(displayLocale.identifier.hasPrefix("zh") ? "更多操作" : "More actions")
                    }
                }.controlSize(.small).disabled(store.isRefreshing)
            }
        }
    }
}

extension SnapshotStore.ActionReason {
    var label: String {
        switch self {
        case .unclear: return "I do not understand"
        case .unsupportedTool: return "My tool does not support this"
        case .noProject: return "I have no project"
        case .notNow: return "Not useful right now"
        }
    }
}

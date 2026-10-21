import SwiftUI

struct TipCard: View {
    let tip: Tip
    @ObservedObject var store: SnapshotStore
    @Environment(\.locale) private var displayLocale

    private var copyTitle: String {
        let language = displayLocale.identifier.hasPrefix("zh") ? "zh-Hans" : "en"
        let bundle = Bundle.module.url(forResource: language, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
        return bundle.localizedString(forKey: "Copy prompt", value: nil, table: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tip.title).font(.title2.bold())
            Text(tip.why).font(.body).foregroundStyle(.secondary)
            if let evidence = tip.evidenceSummary {
                DisclosureGroup {
                    Text(evidence).font(.callout)
                    if let limitation = tip.limitation { Text(limitation).font(.caption).foregroundStyle(.secondary) }
                } label: { Text("Why this suggestion", bundle: .module) }
            }
            ForEach(Array(tip.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)").font(.callout)
            }
            if !tip.promptForClaude.isEmpty {
                HStack {
                    CopyButton(prompt: tip.promptForClaude,
                               title: copyTitle,
                               locale: displayLocale.identifier.hasPrefix("zh") ? "zh" : "en")
                    Button(action: { store.refresh() }) { Text("Check now", bundle: .module) }
                        .disabled(store.isRefreshing)
                }.controlSize(.small)
            }
            if tip.actionId != nil {
                HStack {
                    Button(action: { store.actionFeedback(.later) }) { Text("Later", bundle: .module) }
                    Menu {
                        ForEach(SnapshotStore.ActionReason.allCases, id: \.self) { reason in
                            Button(action: { store.actionFeedback(.notSuitable, reason: reason) }) {
                                Text(LocalizedStringKey(reason.label), bundle: .module)
                            }
                        }
                    } label: { Text("Not suitable", bundle: .module) }
                    Button(action: { store.actionFeedback(.never) }) { Text("Do not suggest again", bundle: .module) }
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

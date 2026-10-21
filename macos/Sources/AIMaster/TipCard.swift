import SwiftUI

struct TipCard: View {
    let tip: Tip
    @ObservedObject var store: SnapshotStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tip.title).font(.title2.bold())
            Text(tip.why).font(.body).foregroundStyle(.secondary)
            ForEach(Array(tip.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)").font(.callout)
            }
            HStack {
                CopyButton(prompt: tip.promptForClaude,
                           title: NSLocalizedString("Copy prompt", bundle: .module, comment: ""),
                           locale: store.locale)
                Button(action: { store.refresh() }) { Text("Check now", bundle: .module) }
                    .disabled(store.isRefreshing)
            }.controlSize(.small)
        }
    }
}

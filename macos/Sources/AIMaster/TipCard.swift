import SwiftUI
import AppKit

struct TipCard: View {
    let tip: Tip
    @ObservedObject var store: SnapshotStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tip.title).font(.headline)
            Text(tip.why).font(.subheadline).foregroundStyle(.secondary)
            ForEach(Array(tip.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)").font(.callout)
            }
            HStack {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tip.promptForClaude, forType: .string)
                }) { Text("Copy prompt", bundle: .module) }
                Button(action: { store.refresh() }) { Text("Check now", bundle: .module) }
                    .disabled(store.isRefreshing)
            }.controlSize(.small)
        }
    }
}

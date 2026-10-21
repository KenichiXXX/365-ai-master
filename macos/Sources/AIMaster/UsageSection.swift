import SwiftUI

struct UsageSection: View {
    let snapshot: Snapshot

    private func usage(_ value: Usage) -> String {
        let cost = String(format: "%.2f", value.costUsd)
        let suffix = snapshot.locale == "zh" ? "（折算）" : " (API-equivalent)"
        return "\(value.tokens.formatted()) tokens · ≈$\(cost)\(suffix)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach((snapshot.tools ?? []).filter { $0.detected || $0.error != nil }) { tool in
                VStack(alignment: .leading, spacing: 4) {
                    Text(SnapshotStore.toolNames[tool.tool] ?? tool.tool).font(.subheadline.bold())
                    if tool.error != nil {
                        Text(snapshot.labels?.toolUnavailable ?? "").foregroundStyle(.orange)
                    } else {
                        if let today = tool.usageToday {
                            Text("Today", bundle: .module).font(.caption.bold())
                            Text(usage(today)).font(.caption)
                        }
                        if let week = tool.usage7d {
                            Text("7 days", bundle: .module).font(.caption.bold())
                            Text(usage(week)).font(.caption)
                        }
                        ForEach(tool.byModel ?? []) { model in
                            Text("\(model.model): \(usage(Usage(tokens: model.tokens, costUsd: model.costUsd)))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let percent = snapshot.quota?.codex?.primaryPct {
                Text("Codex · \(percent, specifier: "%.1f")%")
                    .font(.caption)
                ProgressView(value: min(100, max(0, percent)), total: 100)
            }
        }
    }
}

import SwiftUI

struct UsageSection: View {
    let snapshot: Snapshot
    private var isChinese: Bool { snapshot.locale == "zh" }
    private var numberLocale: Locale { Locale(identifier: isChinese ? "zh_CN" : "en_US") }

    var visibleTools: [ToolUsage] {
        (snapshot.tools ?? []).filter { ($0.detected || $0.error != nil) && ($0.usage7d?.tokens ?? 0) > 0 }
    }

    func topModels(_ tool: ToolUsage) -> [ModelUsage] {
        Array((tool.byModel ?? []).sorted {
            $0.tokens == $1.tokens ? $0.model < $1.model : $0.tokens > $1.tokens
        }.prefix(3))
    }

    private func usage(_ value: Usage) -> String {
        let cost = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value.costUsd)
        let suffix = isChinese ? "（折算）" : " (API-equivalent)"
        return "\(value.tokens.formatted(.number.locale(numberLocale))) tokens · ≈$\(cost)\(suffix)"
    }

    func summary(_ tool: ToolUsage) -> String {
        let today = (tool.usageToday?.tokens ?? 0).formatted(.number.locale(numberLocale))
        let week = tool.usage7d ?? Usage(tokens: 0, costUsd: 0)
        return "\(isChinese ? "今日" : "Today") \(today) · \(isChinese ? "7 日" : "7d") \(usage(week))"
    }

    func quotaLabel(_ quota: CodexQuota) -> String {
        let window: String
        switch quota.primaryWindowMin {
        case 10080: window = isChinese ? "周" : "weekly"
        case 300: window = isChinese ? "5 小时" : "5h"
        case let minutes?: window = "\((Double(minutes) / 60).formatted(.number.locale(Locale(identifier: "en_US"))))h"
        case nil: window = ""
        }
        let percent = String(format: "%.0f", quota.primaryPct ?? 0)
        var label = isChinese ? "Codex \(window)额度 \(percent)%" : "Codex\(window.isEmpty ? "" : " " + window) \(percent)%"
        if let reset = quota.primaryResetsAt {
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = parser.date(from: reset) ?? ISO8601DateFormatter().date(from: reset)
            if let date {
                let formatter = DateFormatter()
                formatter.locale = numberLocale
                formatter.dateFormat = isChinese ? "M月d日" : "MMM d"
                let text = formatter.string(from: date)
                label += isChinese ? " · \(text)重置" : " · resets \(text)"
            }
        }
        return label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(visibleTools) { tool in
                VStack(alignment: .leading, spacing: 4) {
                    Text(SnapshotStore.toolNames[tool.tool] ?? tool.tool).font(.subheadline.bold())
                    if tool.error != nil {
                        Text(snapshot.labels?.toolUnavailable ?? "").foregroundStyle(.orange)
                    } else {
                        Text(summary(tool)).font(.caption).lineLimit(1).minimumScaleFactor(0.65)
                        ForEach(topModels(tool)) { model in
                            Text("\(model.model): \(usage(Usage(tokens: model.tokens, costUsd: model.costUsd)))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let quota = snapshot.quota?.codex, let percent = quota.primaryPct {
                Text(quotaLabel(quota)).font(.caption)
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(percent >= 80 ? Color.orange : Color.accentColor)
                                .frame(width: geometry.size.width * min(100, max(0, percent)) / 100)
                        }
                }
                .frame(height: 8)
                .accessibilityLabel(quotaLabel(quota))
            }
        }
    }
}

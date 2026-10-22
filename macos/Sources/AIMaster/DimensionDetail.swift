import SwiftUI

struct DimensionDetail: View {
    let dimension: Dimension
    let growth: Growth?
    let features: ProFeatures
    let locale: String
    @ObservedObject var store: SnapshotStore
    let back: () -> Void
    private var zh: Bool { locale == "zh" }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.grid) {
                Button(action: back) {
                    Label(zh ? "返回我" : "Back to Me", systemImage: "chevron.left")
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 8) {
                    RingView(score: dimension.score, size: 100)
                    Text(dimension.label).font(Theme.title)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(zh ? "为什么是这个分" : "Why this score").font(Theme.title)
                DisclosureGroup {
                    ForEach(Array((dimension.evidence ?? []).enumerated()), id: \.offset) { _, row in
                        if let days = row.windowDays {
                            Text(zh ? "\(row.label ?? "") · 近 \(days) 天" : "\(row.label ?? "") · \(days) days")
                        }
                        if let limitation = row.limitation { Text(limitation) }
                    }
                } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "评分说明" : "Scoring details") }
                // Adaptive chips keep the real value and target together.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(Array((dimension.evidence ?? []).enumerated()), id: \.offset) { _, row in
                        Text([row.label ?? "", row.value ?? "—", row.target.map { "(\($0))" } ?? ""]
                            .filter { !$0.isEmpty }.joined(separator: " "))
                            .font(Theme.body).padding(8)
                            .bauhausPanel()
                    }
                }
                ForEach(Array((dimension.deductions ?? []).enumerated()), id: \.offset) { _, deduction in
                    HStack(alignment: .top) {
                        Text(deduction.title)
                        Spacer()
                        Text("−\(deduction.points)").bold().foregroundStyle(Theme.ink)
                    }.font(Theme.body)
                }
                Text(zh ? "怎么提升" : "How to improve").font(Theme.title)
                ForEach(Array((dimension.steps ?? []).prefix(3).enumerated()), id: \.offset) { _, step in
                    Text(step).font(Theme.body).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if let prompt = dimension.prompt, !prompt.isEmpty {
                        CopyButton(prompt: prompt, title: zh ? "复制给 Claude" : "Copy prompt", locale: locale)
                    }
                    Button("↻") { store.recheck() }
                        .accessibilityLabel(zh ? "重新扫描" : "Refresh")
                        .disabled(store.isRefreshing)
                }
                if features.growthCurve {
                    Text(zh ? "30 天趋势" : "30-day trend").font(Theme.title)
                    if let growth {
                        GrowthCurve(growth: growth.forDimension(dimension.key), zh: zh)
                    } else {
                        Text(zh ? "正在积累记录" : "Collecting records").foregroundStyle(Theme.secondary)
                    }
                } else {
                    Button { store.showProSettings = true } label: {
                        ProLockLabel(title: zh ? "30 天趋势" : "30-day trend")
                    }.buttonStyle(.plain).accessibilityIdentifier("pro-dimension-trend")
                }
                if !features.isPro {
                    Button { store.showProSettings = true } label: {
                        ProLockLabel(title: zh ? "四维全球排名" : "Global dimension rankings")
                    }.buttonStyle(.plain).accessibilityIdentifier("pro-dimension-ranking")
                }
            }
        }.bauhausTheme()
    }
}

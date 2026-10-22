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
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            Button(action: back) {
                Label(zh ? "返回我" : "Back to Me", systemImage: "chevron.left")
            }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
            HStack(spacing: Theme.cardPadding) {
                RingView(score: dimension.score, size: 100, color: Theme.dimension(dimension.key))
                VStack(alignment: .leading, spacing: Theme.grid * 2) {
                    Text(dimension.label).font(Theme.title)
                        .foregroundStyle(dimension.key == "routing" ? Theme.accentText : Theme.dimension(dimension.key))
                    Text(zh ? "你的 AI 掌握度" : "Your AI proficiency")
                        .font(Theme.label).foregroundStyle(Theme.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.cardPadding).bauhausPanel()
            VStack(alignment: .leading, spacing: Theme.grid * 3) {
                Text(zh ? "为什么是这个分" : "Why this score").font(Theme.sectionTitle)
                DisclosureGroup {
                    ForEach(Array((dimension.evidence ?? []).enumerated()), id: \.offset) { _, row in
                        if let days = row.windowDays {
                            Text(zh ? "\(row.label ?? "") · 近 \(days) 天" : "\(row.label ?? "") · \(days) days")
                        }
                        if let limitation = row.limitation { Text(limitation) }
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .accessibilityLabel(zh ? "评分说明" : "Scoring details")
                }.font(Theme.label).foregroundStyle(Theme.secondary)
                ForEach(Array((dimension.evidence ?? []).enumerated()), id: \.offset) { index, row in
                    if index > 0 { ThemeRule() }
                    HStack(alignment: .top, spacing: Theme.grid * 3) {
                        Text(row.label ?? "")
                        Spacer(minLength: Theme.grid)
                        VStack(alignment: .trailing, spacing: Theme.grid) {
                            Text(row.value ?? "—")
                            if let target = row.target {
                                Text(target).font(Theme.label).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }
                ForEach(Array((dimension.deductions ?? []).enumerated()), id: \.offset) { _, deduction in
                    ThemeRule()
                    HStack(alignment: .top) {
                        Text(deduction.title)
                        Spacer()
                        Text("−\(deduction.points)").foregroundStyle(Theme.secondary)
                    }
                }
            }.padding(Theme.cardPadding).bauhausPanel()
            VStack(alignment: .leading, spacing: Theme.grid * 3) {
                Text(zh ? "怎么提升" : "How to improve").font(Theme.sectionTitle)
                ForEach(Array((dimension.steps ?? []).prefix(3).enumerated()), id: \.offset) { _, step in
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if let prompt = dimension.prompt, !prompt.isEmpty {
                        CopyButton(prompt: prompt, title: zh ? "复制给 Claude" : "Copy prompt", locale: locale)
                    }
                    Button("↻") { store.recheck() }
                        .accessibilityLabel(zh ? "重新扫描" : "Refresh")
                        .disabled(store.isRefreshing)
                }
            }.padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).bauhausPanel()
            VStack(alignment: .leading, spacing: Theme.grid * 3) {
                if features.growthCurve {
                    Text(zh ? "30 天趋势" : "30-day trend").font(Theme.sectionTitle)
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
            }.padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).bauhausPanel()
        }.bauhausTheme()
    }
}

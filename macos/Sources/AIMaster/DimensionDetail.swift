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
        VStack(alignment: .leading, spacing: 16) {
            Button(action: back) {
                Label(zh ? "返回体检" : "Back to check-up", systemImage: "chevron.left")
            }.buttonStyle(.plain)
            VStack(spacing: 8) {
                RingView(score: dimension.score, size: 100)
                Text(dimension.label).font(.title2.bold())
                Text(dimension.verdict ?? (zh ? "记录还不够，暂时无法判断。" : "Not enough records to assess this yet."))
                    .multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
            Text(zh ? "为什么是这个分" : "Why this score").font(.headline)
            ForEach(Array((dimension.evidence ?? []).enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.label ?? row.explanation ?? "").font(.callout)
                    Text(row.value ?? "—").bold()
                    if let target = row.target {
                        Text((zh ? "建议：" : "Target: ") + target).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(Array((dimension.deductions ?? []).enumerated()), id: \.offset) { _, deduction in
                HStack(alignment: .top) {
                    Text(deduction.title)
                    Spacer()
                    Text("−\(deduction.points)").bold().foregroundStyle(.orange)
                }.font(.callout)
            }
            Text(zh ? "怎么提升" : "How to improve").font(.headline)
            ForEach(Array((dimension.steps ?? []).enumerated()), id: \.offset) { _, step in
                Text(step).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let prompt = dimension.prompt, !prompt.isEmpty {
                    CopyButton(prompt: prompt, title: zh ? "复制给 Claude" : "Copy prompt", locale: locale)
                }
                Button(zh ? "做完了，重新体检" : "Done, re-check") { store.recheck() }
                    .disabled(store.isRefreshing)
            }
            if store.isRefreshing {
                ProgressView(zh ? "正在体检…" : "Checking…")
            }
            if features.growthCurve {
                Text(zh ? "30 天趋势" : "30-day trend").font(.headline)
                if let growth {
                    GrowthCurve(growth: growth.forDimension(dimension.key), zh: zh)
                } else {
                    Text(zh ? "正在积累记录" : "Collecting records").foregroundStyle(.secondary)
                }
            } else {
                Text(zh ? "Pro 可看 30 天趋势" : "Pro unlocks the 30-day trend").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

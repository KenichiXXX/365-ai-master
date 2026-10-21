import SwiftUI

struct CheckupTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 10) {
                RingView(score: snapshot.overall?.score ?? 0)
                if let village = snapshot.village {
                    Text(village.rankTitle).font(.title3.bold())
                    Text(progressLine).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity).padding(.top, 8)
            DimensionRings(dimensions: snapshot.dimensions ?? [])
            Divider()
            if let tip = snapshot.todayTip { TipCard(tip: tip, store: store) }
            if let usage = snapshot.usageSummary {
                Text(usage.caption(locale: snapshot.locale ?? store.locale))
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var progressLine: String {
        let village = snapshot.village
        let current = village?.quests.firstIndex(where: { $0.key == village?.current }).map { $0 + 1 }
            ?? village?.quests.count ?? 0
        let days = snapshot.streak?.days ?? 0
        return snapshot.locale == "zh" ? "新手村第 \(current) 关 · 连续 \(days) 天"
            : "Village quest \(current) · \(days)-day streak"
    }
}

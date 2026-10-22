import SwiftUI
import AppKit

struct DiscoverPage: View {
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void
    @State private var kind: DiscoverRanking = .skill

    private var snapshot: Snapshot? { store.snapshot }
    private var rows: [Ranking] {
        switch kind {
        case .skill: return snapshot?.rankings?.skill ?? []
        case .agent: return snapshot?.rankings?.agent ?? []
        case .product: return snapshot?.rankings?.product ?? []
        case .learnable: return []
        }
    }

    var body: some View {
        VStack(spacing: Theme.gap) {
            if let snapshot, !DiscoverContent.picks(snapshot).isEmpty { picks(snapshot) }
            Segmented(selection: $kind, options: [.skill, .agent, .product]) { kind in
                switch kind {
                case .skill: return tr(locale, "Skill 榜", "Skills")
                case .agent: return tr(locale, "Agent 榜", "Agents")
                default: return tr(locale, "产品榜", "Products")
                }
            }
            list
            if let rankings = snapshot?.rankings {
                Text(rankings.footnote(locale: locale)).font(Theme.caption).foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
        }
    }

    private func picks(_ snapshot: Snapshot) -> some View {
        let rows = DiscoverContent.picks(snapshot)
        let all = (snapshot.rankings?.skill ?? []) + (snapshot.rankings?.agent ?? [])
        let reason = DiscoverContent.weakest(snapshot).map { DiscoverContent.reason(dimension: $0, locale: locale) } ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Label(tr(locale, "为你推荐 · ", "For you · ") + reason, systemImage: "scope")
                .font(Theme.captionStrong).foregroundStyle(Theme.goldText)
            ForEach(rows, id: \.url) { row in
                Button { Self.openRow(row) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DiscoverContent.shortName(row, in: all)).font(Theme.bodyStrong)
                            Text(row.tagline).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.goldText)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.card(fill: Theme.goldSoft, stroke: Theme.gold.opacity(0.3))
    }

    private var list: some View {
        let visible = store.features.discoverRankings(rows)
        return VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, row in
                if index > 0 { Hairline() }
                Button { Self.openRow(row) } label: {
                    RankingRow(position: index + 1, row: row, name: DiscoverContent.shortName(row, in: rows), locale: locale)
                }.buttonStyle(.plain)
            }
            if rows.isEmpty {
                Text(tr(locale, "榜单还没下载，过一会儿再来", "Rankings not downloaded yet"))
                    .font(Theme.body).foregroundStyle(Theme.secondary).padding(.vertical, 16)
            }
            if DiscoverContent.hasLockedRows(count: rows.count, isPro: store.isPro) {
                Hairline()
                Button { open(.pro) } label: {
                    HStack {
                        Text(tr(locale, "第 11–\(min(20, rows.count)) 名", "Ranks 11–\(min(20, rows.count))")).foregroundStyle(Theme.secondary)
                        Spacer()
                        ProLock()
                    }.font(Theme.body).padding(.vertical, 11).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.cardPadding).padding(.vertical, 2)
        .card(padding: 0)
    }

    static func openRow(_ row: Ranking) {
        if PublicContent.safeURL(row.url), let url = URL(string: row.url) { NSWorkspace.shared.open(url) }
    }
}

struct RankingRow: View {
    let position: Int
    let row: Ranking
    let name: String
    let locale: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(position)").font(Theme.number(13, .bold)).monospacedDigit()
                .foregroundStyle(position <= 3 ? Theme.goldText : Theme.tertiary).frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(Theme.bodyStrong).lineLimit(1)
                    if let tag = row.beginnerTag(locale: locale) { Chip(text: tag, tone: .good) }
                }
                Text(row.tagline).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if let weekly = row.stars7d, weekly > 0 {
                    Text("+" + weekly.formatted(.number.locale(Locale(identifier: "en_US")))).font(Theme.number(12)).foregroundStyle(Theme.goodText)
                    Text(tr(locale, "本周", "this week")).font(Theme.caption).foregroundStyle(Theme.tertiary)
                } else if let stars = row.stars {
                    Text("★ " + UsageSummary.tokens(stars, locale: "en")).font(Theme.number(12)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .help(row.url)
    }
}

struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button { withAnimation(Theme.motion) { selection = option } } label: {
                    Text(title(option))
                        .font(selection == option ? Theme.bodyStrong : Theme.body)
                        .foregroundStyle(selection == option ? Theme.ink : Theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

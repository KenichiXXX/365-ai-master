import SwiftUI
import AppKit

struct TodaySkillTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    @State private var selectedRanking: DiscoverRanking = .skill
    private var locale: String { snapshot.locale ?? store.locale }
    private var zh: Bool { locale == "zh" }

    init(snapshot: Snapshot, store: SnapshotStore, ranking: DiscoverRanking = .skill) {
        self.snapshot = snapshot
        self.store = store
        _selectedRanking = State(initialValue: ranking)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.grid * 2) {
            if let card = snapshot.book?.today {
                VStack(alignment: .leading, spacing: Theme.grid) {
                    Text("TODAY'S PICK").font(Theme.label).tracking(2).foregroundStyle(Theme.fixedInk)
                    Text(ActionCopy.line(card.title, locale: locale, hanLimit: 14, englishLimit: 32))
                        .font(Theme.title).lineLimit(1)
                    CopyButton(prompt: card.prompt, title: zh ? "复制试一下" : "Copy & try", locale: locale,
                               onCopied: { store.practice(id: card.id, operation: "copy") })
                        .disabled(store.isRefreshing)
                }.padding(Theme.grid * 2).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Theme.fixedInk).background(Theme.yellow)
                    .accessibilityIdentifier("today-pick")
            }
            let picks = DiscoverContent.picks(snapshot)
            if !picks.isEmpty {
                VStack(alignment: .leading, spacing: Theme.grid) {
                    Text(zh ? "为你推荐" : "For you").font(Theme.label)
                    ForEach(picks, id: \.url) { row in
                        Button { openRepository(row) } label: {
                            VStack(alignment: .leading, spacing: Theme.grid) {
                                Text(DiscoverContent.shortName(row, in: recommendationRows)).font(Theme.title).lineLimit(1)
                                Text(ActionCopy.benefit(DiscoverContent.reason(
                                    dimension: DiscoverContent.weakest(snapshot) ?? "", locale: locale), locale: locale))
                                    .font(Theme.body).foregroundStyle(Theme.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            rankingTabs
            VStack(alignment: .leading, spacing: Theme.grid) {
                if selectedRanking == .learnable {
                    ForEach(Array(store.features.discoverRankings(cards).enumerated()), id: \.element.id) { index, card in
                        Button { store.reminderCard = card } label: {
                            PicksRankingRow(position: index + 1, name: card.title,
                                tagline: card.why, tag: card.lit ? (zh ? "已点亮" : "Lit") : nil)
                        }.buttonStyle(.plain)
                        ThemeRule()
                    }
                } else {
                    ForEach(Array(store.features.discoverRankings(rows).enumerated()), id: \.offset) { index, row in
                        Button { openRepository(row) } label: {
                            PicksRankingRow(position: index + 1,
                                name: DiscoverContent.shortName(row, in: rows), tagline: row.tagline,
                                metric: DiscoverContent.metric(row, locale: locale), weekly: row.stars7d, locale: locale,
                                tag: row.installed == true || row.installationHint == true ? (zh ? "已装" : "Installed") : nil)
                        }.buttonStyle(.plain)
                        ThemeRule()
                    }
                }
                if rowCount == 0 {
                    Text(zh ? "暂无榜单" : "No rankings yet").font(Theme.body).foregroundStyle(Theme.secondary)
                }
                if DiscoverContent.hasLockedRows(count: rowCount, isPro: store.isPro) {
                    Button { store.showProSettings = true } label: {
                        HStack(spacing: Theme.grid) {
                            Image(systemName: "lock.fill").font(Theme.label)
                                .frame(width: 20, height: 20).bauhausPanel()
                            Text(zh ? "第 11–20 名 · PRO 解锁" : "Ranks 11–20 · Unlock with PRO")
                                .font(Theme.title).lineLimit(1)
                            Spacer(minLength: 0)
                        }.padding(.vertical, Theme.grid).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("rankings-pro-lock")
                }
            }
            if let rankings = snapshot.rankings {
                Text(rankings.footnote(locale: locale)).font(Theme.label).foregroundStyle(Theme.secondary)
                    .lineLimit(1).help(rankings.footnote(locale: locale))
            }
        }.bauhausTheme()
    }

    private var rankingTabs: some View {
        HStack(spacing: Theme.grid * 2) {
            ForEach(DiscoverRanking.allCases, id: \.self) { kind in
                Button { selectedRanking = kind } label: {
                    Text(kind.title(zh: zh)).font(Theme.title)
                        .foregroundStyle(selectedRanking == kind ? Theme.ink : Theme.secondary)
                        .padding(.vertical, Theme.grid)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selectedRanking == kind ? Theme.ink : .clear).frame(height: 2)
                        }
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selectedRanking == kind ? .isSelected : [])
            }
        }
    }

    private var recommendationRows: [Ranking] { (snapshot.rankings?.skill ?? []) + (snapshot.rankings?.agent ?? []) }
    private var cards: [SkillCard] { snapshot.book?.cards ?? [] }
    private var rowCount: Int { selectedRanking == .learnable ? cards.count : rows.count }
    private var rows: [Ranking] {
        switch selectedRanking {
        case .skill: return snapshot.rankings?.skill ?? []
        case .agent: return snapshot.rankings?.agent ?? []
        case .product: return snapshot.rankings?.product ?? []
        case .learnable: return []
        }
    }

    private func openRepository(_ row: Ranking) {
        if PublicContent.safeURL(row.url), let url = URL(string: row.url) { NSWorkspace.shared.open(url) }
    }
}

private struct PicksRankingRow: View {
    let position: Int
    let name: String
    let tagline: String
    var metric: String = ""
    var weekly: Int? = nil
    var locale: String = "en"
    var tag: String? = nil

    private var rankColor: Color {
        switch position {
        case 1: return Theme.red
        case 2: return Theme.blue
        default: return Theme.ink
        }
    }

    var body: some View {
        HStack(spacing: Theme.grid) {
            Text("\(position)").font(Theme.label).monospacedDigit()
                .foregroundStyle(position <= 2 ? Theme.fixedPaper : position == 3 ? Theme.paper : Theme.ink)
                .frame(width: 20, height: 20)
                .background(position <= 3 ? rankColor : Color.clear)
                .overlay(Rectangle().strokeBorder(rankColor, lineWidth: Theme.ruleWidth))
            VStack(alignment: .leading, spacing: Theme.grid) {
                HStack(spacing: Theme.grid) {
                    Text(name).font(Theme.title).lineLimit(1)
                    if let tag {
                        Text(tag).font(Theme.label).lineLimit(1).fixedSize()
                            .padding(.horizontal, 4).padding(.vertical, 2).bauhausPanel()
                    }
                }
                Text(tagline).font(Theme.body).foregroundStyle(Theme.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !metric.isEmpty {
                Text(metric).font(Theme.label).monospacedDigit().lineLimit(1).fixedSize()
                    .foregroundStyle((weekly ?? 0) > 0 ? Theme.red : Theme.secondary)
                    .accessibilityLabel(weekly != nil ? metric + (locale == "zh" ? " 本周增长" : " weekly growth") : metric)
            }
        }.padding(.vertical, Theme.grid).contentShape(Rectangle())
    }
}

struct PracticeControls: View {
    let card: SkillCard
    @ObservedObject var store: SnapshotStore
    let locale: String
    private var zh: Bool { locale == "zh" }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.grid) {
                DisclosureGroup {
                    Text(card.evidenceText(locale: locale)).font(Theme.body)
                    ForEach(Array((card.steps ?? []).prefix(3).enumerated()), id: \.offset) { index, step in
                        Text(step).font(Theme.body)
                    }
                    if let signal = card.expectedSignal { Text(signal).font(Theme.body) }
                    if let limitations = card.limitations { Text(limitations).font(Theme.body) }
                    if card.automaticSupported == false {
                        Text(zh ? "当前工具暂不支持自动验证" : "Automatic verification is not supported for this tool")
                            .font(Theme.body)
                    }
                    if store.practiceFeedbackID == card.id, let feedback = store.triedFeedback {
                        Text(feedback == .lit ? (zh ? "已点亮" : "Lit up") : (zh ? "等待新记录" : "Waiting for new records"))
                            .font(Theme.body)
                    }
                    Button(zh ? "学会了" : "Learned it") { store.markTried(card) }
                    Menu {
                        Button(zh ? "开始实践" : "Start practice") { store.practice(id: card.id, operation: "start") }
                        if card.isSelfReport {
                            Button(zh ? "已尝试（自报）" : "Tried (self-reported)") { store.markTried(card) }
                        }
                        Button(zh ? "换一个" : "Skip once") { store.practice(id: card.id, operation: "skip") }
                    } label: { Text("⋯") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(zh ? "更多操作" : "More actions")
                } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "练习说明" : "Practice details") }
                CopyButton(prompt: card.prompt, title: zh ? "复制试一下" : "Copy & try", locale: locale,
                           onCopied: { store.practice(id: card.id, operation: "copy") })
                    .disabled(store.isRefreshing)
            }
        }.bauhausTheme()
    }
}

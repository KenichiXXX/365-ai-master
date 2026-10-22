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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            if let card = snapshot.book?.today {
                todayPick(card)
            }
            let picks = DiscoverContent.picks(snapshot)
            let benefits = DiscoverContent.benefits(picks, locale: locale)
            if !picks.isEmpty {
                VStack(alignment: .leading, spacing: Theme.grid * 2) {
                    Text(zh ? "为你推荐" : "For you").font(Theme.sectionTitle)
                    ForEach(Array(picks.enumerated()), id: \.element.url) { index, row in
                        Button { openRepository(row) } label: {
                            HStack(spacing: Theme.grid * 2) {
                                Text(snapshot.rankings?.skill?.contains(where: { $0.url == row.url }) == true ? "Skill" : "Agent")
                                    .font(Theme.label).foregroundStyle(Theme.secondary)
                                    .frame(width: Theme.grid * 8, alignment: .leading)
                                Text(DiscoverContent.shortName(row, in: recommendationRows))
                                    .font(Theme.body).foregroundStyle(Theme.ink).fixedSize()
                                Text("· " + benefits[index])
                                    .font(Theme.body).foregroundStyle(Theme.secondary).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("↗").foregroundStyle(Theme.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .help(DiscoverContent.shortName(row, in: recommendationRows))
                            .accessibilityLabel("\(DiscoverContent.shortName(row, in: recommendationRows)), \(benefits[index])")
                    }
                }
            }
            VStack(alignment: .leading, spacing: Theme.grid * 2) {
                rankingTabs
                rankingList
            }
            if let rankings = snapshot.rankings {
                Text(rankings.footnote(locale: locale)).font(Theme.label).foregroundStyle(Theme.secondary)
                    .lineLimit(1).help(rankings.footnote(locale: locale))
            }
        }.bauhausTheme()
    }

    private func todayPick(_ card: SkillCard) -> some View {
        VStack(alignment: .leading, spacing: Theme.grid * 2) {
            HStack(alignment: .top, spacing: Theme.grid * 3) {
                VStack(alignment: .leading, spacing: Theme.grid * 2) {
                    Text(zh ? "今日推荐" : "TODAY'S PICK")
                        .font(Theme.label).foregroundStyle(Theme.secondary)
                    Text(ActionCopy.line(card.title, locale: locale, hanLimit: 14, englishLimit: 32))
                        .font(Theme.title).lineLimit(1).minimumScaleFactor(0.8)
                }.frame(maxWidth: .infinity, alignment: .leading)
                RoundedRectangle(cornerRadius: Theme.grid)
                    .fill(Theme.accent).frame(width: Theme.grid * 4, height: Theme.grid * 4)
                    .accessibilityHidden(true)
            }
            Text(ActionCopy.line(card.why, locale: locale, hanLimit: 24, englishLimit: 64))
                .font(Theme.label).foregroundStyle(Theme.secondary).lineLimit(1)
            CopyButton(prompt: card.prompt, title: zh ? "复制试一下 ↗" : "Copy & try ↗", locale: locale,
                       onCopied: { store.practice(id: card.id, operation: "copy") }, primary: true)
                .disabled(store.isPerformingAction)
            if store.isPerformingAction {
                Image(systemName: "info.circle")
                    .help(zh ? "正在保存操作，请稍候" : "Saving your action; please wait")
            }
        }.padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .accessibilityIdentifier("today-pick")
    }

    private var rankingList: some View {
        VStack(spacing: 0) {
            if selectedRanking == .learnable {
                ForEach(Array(store.features.discoverRankings(cards).enumerated()), id: \.element.id) { index, card in
                    if index > 0 { ThemeRule() }
                    Button { store.reminderCard = card } label: {
                        PicksRankingRow(position: index + 1, name: card.title,
                            tagline: card.why, tag: card.lit ? (zh ? "已点亮" : "Lit") : nil)
                    }.buttonStyle(.plain)
                }
            } else {
                ForEach(Array(store.features.discoverRankings(rows).enumerated()), id: \.offset) { index, row in
                    if index > 0 { ThemeRule() }
                    Button { openRepository(row) } label: {
                        PicksRankingRow(position: index + 1,
                            name: DiscoverContent.shortName(row, in: rows), tagline: row.tagline,
                            metric: DiscoverContent.metric(row, locale: locale), weekly: row.stars7d, locale: locale,
                            tag: row.installed == true || row.installationHint == true ? (zh ? "已装" : "Installed") : row.beginnerTag(locale: locale))
                    }.buttonStyle(.plain)
                }
            }
            if rowCount == 0 {
                Text(zh ? "暂无榜单" : "No rankings yet").font(Theme.body).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Theme.cardPadding)
            }
            if DiscoverContent.hasLockedRows(count: rowCount, isPro: store.isPro) {
                ThemeRule()
                Button { store.showProSettings = true } label: {
                    HStack(spacing: Theme.grid) {
                        Text(zh ? "第 11–20 名" : "Ranks 11–20").foregroundStyle(Theme.secondary)
                        Spacer(minLength: Theme.grid)
                        Text(zh ? "PRO 解锁 ↗" : "Unlock with PRO ↗")
                    }.font(Theme.label).padding(.vertical, Theme.grid * 3).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("rankings-pro-lock")
            }
        }.padding(.horizontal, Theme.grid * 3)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.listRadius))
    }

    private var rankingTabs: some View {
        HStack(spacing: Theme.grid) {
            ForEach(DiscoverRanking.allCases, id: \.self) { kind in
                Button { selectedRanking = kind } label: {
                    Text(kind.title(zh: zh)).font(Theme.label)
                        .fontWeight(selectedRanking == kind ? .semibold : .regular)
                        .foregroundStyle(selectedRanking == kind ? Theme.ink : Theme.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, Theme.grid)
                        .background {
                            if selectedRanking == kind {
                                RoundedRectangle(cornerRadius: Theme.buttonRadius).fill(Theme.surface)
                                    .shadow(color: Theme.ink.opacity(0.08), radius: 2, y: 1)
                            }
                        }
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selectedRanking == kind ? .isSelected : [])
                    .accessibilityIdentifier("ranking-tab-\(kind.rawValue)")
            }
        }.padding(Theme.grid)
            .background(Theme.hairline, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .animation(reduceMotion ? nil : .easeInOut(duration: Theme.feedbackDuration), value: selectedRanking)
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

    var body: some View {
        HStack(spacing: Theme.grid * 3) {
            Text(String(format: "%02d", position)).font(Theme.label).monospacedDigit()
                .foregroundStyle(Theme.secondary).frame(width: Theme.grid * 4, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.grid) {
                HStack(spacing: Theme.grid) {
                    Text(name).font(Theme.body).lineLimit(1)
                    if let tag {
                        Text(tag).font(Theme.label).foregroundStyle(Theme.secondary).lineLimit(1).fixedSize()
                    }
                }
                Text(tagline).font(Theme.label).foregroundStyle(Theme.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !metric.isEmpty {
                Text(metric).font(Theme.label).monospacedDigit().lineLimit(1).fixedSize()
                    .foregroundStyle((weekly ?? 0) > 0 ? Theme.accentText : Theme.secondary)
                    .accessibilityLabel(weekly != nil ? metric + (locale == "zh" ? " 本周增长" : " weekly growth") : metric)
            }
        }.padding(.vertical, Theme.grid * 3).contentShape(Rectangle())
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
                    .disabled(store.isPerformingAction)
            }
        }.bauhausTheme()
    }
}

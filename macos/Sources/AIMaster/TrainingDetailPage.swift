import SwiftUI

struct TrainingDetailPage: View {
    let destination: TrainingDestination
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    @State private var selected: String?
    @State private var showShareCard = false
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.grid * 2) {
            if destination == .today || destination == .challenge {
                if let game = snapshot.trainingGame {
                    TrainingGameDetailView(game: game, store: store, zh: zh, destination: destination)
                } else {
                    Text(zh ? "暂无修炼记录" : "No training records yet")
                }
            }
            if destination == .village, let village = snapshot.village {
                VStack(alignment: .leading, spacing: Theme.grid) {
                    villagePath(village)
                    if let quest = village.quests.first(where: { $0.key == village.current }) {
                        DisclosureGroup(quest.title) {
                            Text(quest.evidenceLabel ?? NSLocalizedString("Historical record, not evidence of this practice", bundle: .module, comment: ""))
                                .font(Theme.label)
                            FirstPracticeView(store: store)
                        }
                    }
                    if village.current == nil {
                        Text(zh ? "出师 ✓" : "Graduated ✓")
                            .font(Theme.title).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.grid * 2).bauhausPanel()
                    } else if let tip = snapshot.todayTip, tip.source.kind == "quest",
                              tip.source.ref == village.current {
                        TipCard(tip: tip, store: store)
                            .padding(Theme.grid * 2).frame(maxWidth: .infinity, alignment: .leading)
                            .bauhausPanel()
                    }
                }
            }
            if destination == .book, let book = snapshot.book {
                VStack(alignment: .leading, spacing: Theme.grid) {
                    Text(zh ? "配置存在 \(book.configurationCount ?? 0) · 自报 \(book.selfReportCount ?? 0)"
                         : "Configuration \(book.configurationCount ?? 0) · Self-reported \(book.selfReportCount ?? 0)")
                        .font(Theme.label).foregroundStyle(Theme.secondary)
                    Text((book.groups ?? []).map { "\($0.title) \($0.lit)/\($0.total)" }.joined(separator: " · "))
                        .font(Theme.body).foregroundStyle(Theme.secondary)
                    if (book.groups ?? []).isEmpty {
                        ForEach(book.cards) { card in skillRow(card) }
                    }
                    ForEach(book.groups ?? []) { group in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(book.cards.filter { $0.level == group.level }) { card in
                                    skillRow(card)
                                }
                            }.padding(.top, 8)
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.grid) {
                                Text("\(group.title) \(group.lit)/\(group.total)").font(Theme.title)
                                Text(missingSummary(group, book: book))
                                    .font(Theme.label).foregroundStyle(Theme.secondary).lineLimit(2)
                            }
                        }.padding(Theme.grid * 2).bauhausPanel()
                    }
                }
            }
            if destination == .badges, let book = snapshot.book {
                VStack(alignment: .leading, spacing: 8) {
                    Text(zh ? "下一枚徽章" : "Next badge").font(Theme.title)
                    if let badge = book.nextBadge {
                        HStack {
                            Text(badge.title)
                            Spacer()
                            Text("\(badge.have)/\(badge.need)").monospacedDigit()
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Theme.paper)
                                Rectangle().fill(Theme.blue)
                                    .frame(width: geometry.size.width * min(1, max(0, Double(badge.have) / Double(max(1, badge.need)))))
                            }
                        }.frame(height: Theme.grid).overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.ruleWidth))
                            .accessibilityLabel(badge.title)
                            .accessibilityValue("\(badge.have)/\(badge.need)")
                    } else {
                        Text(zh ? "徽章已集齐 ✓" : "All badges earned ✓")
                    }
                    let earned = (snapshot.badges ?? []).filter(\.earned).map(\.title)
                    DisclosureGroup {
                        Text(earned.isEmpty ? (zh ? "尚未获得徽章" : "No badges yet") : earned.joined(separator: " · "))
                            .font(Theme.body)
                    } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "已获徽章" : "Earned badges") }
                }.padding(Theme.grid).bauhausPanel()
            }
            if destination == .badges {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: Theme.grid) {
                    ForEach(snapshot.badges ?? []) { badge in
                        VStack(alignment: .leading, spacing: Theme.grid) {
                            Image(systemName: badge.earned ? "checkmark.seal.fill" : "seal")
                            Text(badge.title).font(Theme.label)
                        }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                            .padding(Theme.grid).bauhausPanel()
                            .foregroundStyle(badge.earned ? Theme.ink : Theme.secondary)
                            .accessibilityLabel(badge.title + (badge.earned ? " ✓" : ""))
                    }
                }
                ForEach(snapshot.trainingGame?.weeklyBadges ?? [], id: \.self) { badge in
                    Label(badge.replacingOccurrences(of: "weekly:", with: ""), systemImage: "rosette")
                }
            }
            if destination == .book || destination == .village {
                if let calendar = snapshot.book?.practiceCalendar { PracticeCalendar(data: calendar) }
                Button(shareCopy("Share my practice", snapshot.locale ?? "en")) { showShareCard = true }
                    .sheet(isPresented: $showShareCard) { ShareCard(snapshot: snapshot, store: store) }
            }
        }.bauhausTheme()
    }

    private func villagePath(_ village: Village) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(village.quests.enumerated()), id: \.element.id) { index, quest in
                if index > 0 {
                    Rectangle().fill(Theme.ink).frame(height: Theme.ruleWidth)
                }
                Text(quest.status == "passed" ? "✓" : String(index + 1))
                    .font(Theme.label).frame(width: 28, height: 28)
                    .foregroundStyle(quest.status == "passed" ? Theme.paper :
                                        quest.status == "current" ? Theme.ink : Theme.secondary)
                    .background(quest.status == "passed" ? Theme.ink : Theme.paper, in: Rectangle())
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.ruleWidth))
                    .accessibilityLabel("\(index + 1). \(quest.title), \(quest.status)")
            }
        }
    }

    private func missingSummary(_ group: SkillGroup, book: SkillBook) -> String {
        if group.missing.isEmpty { return zh ? "已全部点亮 ✓" : "All lit ✓" }
        if !zh { return "\(group.missing.count) to go" }
        let titles = group.missing.prefix(2).compactMap { id in book.cards.first { $0.id == id }?.title }
        return "还差：" + titles.joined(separator: "、") + (group.missing.count > 2 ? "…" : "")
    }

    private func skillRow(_ card: SkillCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                selected = selected == card.id ? nil : card.id
                if selected == card.id { store.practice(id: card.id, operation: "seen") }
            }) {
                HStack {
                    Text(card.lit ? "✓" : "○").foregroundStyle(card.lit ? Theme.ink : Theme.secondary)
                    Text(card.title)
                    Spacer()
                    Text(card.evidenceText(locale: snapshot.locale ?? store.locale)).font(Theme.label).foregroundStyle(Theme.secondary)
                    Image(systemName: selected == card.id ? "chevron.up" : "chevron.down").font(Theme.label)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if selected == card.id {
                SkillCardDetails(card: card, todayID: snapshot.book?.today?.id,
                                 store: store, locale: snapshot.locale ?? store.locale)
            }
        }.padding(.vertical, Theme.grid)
    }
}

struct SkillCardDetails: View {
    let card: SkillCard
    let todayID: String?
    @ObservedObject var store: SnapshotStore
    let locale: String

    var body: some View {
        Group {
            if store.features.canLearn(card, todayID: todayID) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.why).font(Theme.body).foregroundStyle(Theme.secondary)
                    DisclosureGroup {
                        Text(card.prompt).font(Theme.body).textSelection(.enabled)
                    } label: { Image(systemName: "info.circle").accessibilityLabel(locale == "zh" ? "查看指令" : "View prompt") }
                    PracticeControls(card: card, store: store, locale: locale)
                }
            } else {
                Button { store.showProSettings = true } label: {
                    ProLockLabel(title: locale == "zh" ? "随时选学这张卡" : "Learn this card anytime")
                }.buttonStyle(.plain).accessibilityIdentifier("pro-skill-detail")
            }
        }.bauhausTheme()
    }
}

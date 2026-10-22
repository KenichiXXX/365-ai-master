import SwiftUI

struct PathPage: View {
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void
    @State private var expanded: String?

    var body: some View {
        VStack(spacing: Theme.gap) {
            if let book = store.snapshot?.book {
                summary(book)
                ForEach(PathLevel.levels(book, locale: locale)) { level in
                    section(level, todayID: book.today?.id)
                }
                Button { open(.share) } label: { Label(tr(locale, "分享我的段位", "Share my rank"), systemImage: "square.and.arrow.up") }
                    .buttonStyle(SecondaryButtonStyle(expand: true))
            }
        }
        .onAppear { expanded = store.snapshot?.book?.today?.id }
    }

    private func summary(_ book: SkillBook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(book.lit)").font(Theme.number(36)).monospacedDigit()
                Text("/ \(book.total)").font(Theme.number(17, .medium)).foregroundStyle(Theme.secondary)
                Text(tr(locale, "招已点亮", "skills lit")).font(Theme.body).foregroundStyle(Theme.secondary)
                Spacer()
                if let days = store.snapshot?.streak?.days {
                    Chip(text: tr(locale, "连续 \(days) 天", "\(days)-day streak"), tone: .gold, icon: "flame.fill")
                }
            }
            ProgressBar(value: Double(book.lit) / Double(max(1, book.total)), height: 8)
            Text(tr(locale, "每天一招。日志里看得出来的，用一次就自动点亮；看不出来的，学会后自己点。",
                    "One skill a day. Skills your logs can show light up on their own; the rest you mark yourself."))
                .font(Theme.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }.card()
    }

    private func section(_ level: PathLevel, todayID: String?) -> some View {
        let locked = !store.isPro && level.level > 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "\(level.title) · \(level.lit)/\(level.cards.count)")
                if locked { ProLock() }
            }
            VStack(spacing: 0) {
                ForEach(Array(level.cards.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { Hairline().padding(.leading, 44) }
                    PathNode(card: card, isToday: card.id == todayID,
                             canLearn: store.features.canLearn(card, todayID: todayID),
                             expanded: expanded == card.id, store: store, locale: locale, open: open) {
                        withAnimation(Theme.motion) { expanded = expanded == card.id ? nil : card.id }
                    }
                }
            }
            .padding(.horizontal, Theme.cardPadding).padding(.vertical, 2)
            .card(padding: 0)
        }
    }
}

struct PathNode: View {
    let card: SkillCard
    let isToday: Bool
    let canLearn: Bool
    let expanded: Bool
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    dot
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(card.title).font(Theme.body).foregroundStyle(canLearn || card.lit ? Theme.ink : Theme.secondary)
                            if isToday && !card.lit { Chip(text: tr(locale, "今天", "Today"), tone: .gold) }
                        }
                        Text(card.why).font(Theme.caption).foregroundStyle(Theme.tertiary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded { detail.padding(.leading, 44).padding(.bottom, 10) }
        }
    }

    @ViewBuilder
    private var dot: some View {
        ZStack {
            if card.lit {
                Circle().fill(Theme.gold)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.onGold)
            } else if !canLearn {
                Circle().fill(Theme.inset)
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
            } else if isToday {
                Circle().strokeBorder(Theme.gold, lineWidth: 2)
                Circle().fill(Theme.gold).padding(8)
            } else {
                Circle().strokeBorder(Theme.hairline, lineWidth: 1.5)
            }
        }.frame(width: 28, height: 28)
    }

    @ViewBuilder
    private var detail: some View {
        if canLearn || card.lit {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.lit ? tr(locale, "已点亮。复用越多，越熟练。", "Lit. The more you reuse it, the better.")
                     : card.autoDetects ? tr(locale, "用一次，日志里看得到，就会自动点亮。", "Use it once and your logs light it up.")
                     : tr(locale, "日志看不出这一招，学会后点「我学会了」。", "Logs can't show this one. Mark it when you've got it."))
                    .font(Theme.caption).foregroundStyle(Theme.secondary)
                Text(card.prompt).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(3)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                HStack(spacing: 8) {
                    CopyButton(prompt: card.prompt, title: tr(locale, "复制提示词", "Copy prompt"), locale: locale,
                               onCopied: { store.practice(id: card.id, operation: "copy") }, primary: !card.lit)
                    if !card.lit && !card.autoDetects {
                        Button(tr(locale, "我学会了", "I've got it")) { store.markTried(card) }
                            .buttonStyle(SecondaryButtonStyle()).disabled(store.isRefreshing)
                    }
                }
            }
        } else {
            Button { open(.pro) } label: {
                HStack {
                    Text(tr(locale, "进阶和高手的招式，Pro 解锁", "Intermediate and Advanced skills unlock with Pro"))
                        .font(Theme.caption).foregroundStyle(Theme.goldText)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.goldText)
                }.padding(10).background(Theme.goldSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }.buttonStyle(.plain)
        }
    }
}

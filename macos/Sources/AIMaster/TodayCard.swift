import SwiftUI

struct TodayCard: View {
    let card: SkillCard
    let book: SkillBook?
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void

    private var status: TodayStatus { TodayStatus.of(card, feedback: store.feedback(for: card.id)) }
    private var levelTitle: String? {
        book.flatMap { PathLevel.levels($0, locale: locale).first { $0.level == card.level }?.title }
    }
    private var position: Int { (book?.lit ?? 0) + (card.lit ? 0 : 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title).font(.system(size: 17, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(card.why).font(Theme.body).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            switch status {
            case .ready: ready
            case .waiting: waiting
            case .done: done
            }
        }
        .card(fill: status == .done ? Theme.goodSoft : Theme.goldSoft,
              stroke: (status == .done ? Theme.good : Theme.gold).opacity(0.35))
        .animation(Theme.motion, value: status)
        .accessibilityIdentifier("today-card")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label(tr(locale, "今日一招", "Today's skill"), systemImage: status == .done ? "checkmark.seal.fill" : "sparkles")
                .font(Theme.captionStrong)
                .foregroundStyle(status == .done ? Theme.goodText : Theme.goldText)
            if let levelTitle { Chip(text: levelTitle, tone: .neutral) }
            Spacer()
            if let total = book?.total {
                Text(tr(locale, "第 \(position) / \(total) 招", "\(position) of \(total)"))
                    .font(Theme.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var promptPreview: some View {
        Text(card.prompt)
            .font(Theme.caption).foregroundStyle(Theme.secondary)
            .lineLimit(2)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                StepRow(number: 1, text: tr(locale, "复制提示词", "Copy the prompt"), fill: Theme.surface)
                StepRow(number: 2, text: tr(locale, "在 Claude Code 或 Codex 里发出去", "Send it in Claude Code or Codex"), fill: Theme.surface)
                StepRow(number: 3, text: card.autoDetects ? tr(locale, "用过一次，这里会自动点亮", "Use it once and this lights up by itself")
                                        : tr(locale, "学会后回来点「我学会了」", "Come back and tap “I've got it”"), fill: Theme.surface)
            }
            promptPreview
            HStack(spacing: 8) {
                CopyButton(prompt: card.prompt, title: tr(locale, "复制提示词", "Copy prompt"), locale: locale,
                           onCopied: { store.practice(id: card.id, operation: "copy") }, primary: true)
                    .disabled(store.isPerformingAction)
                secondaryAction
            }
        }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hourglass").foregroundStyle(Theme.goldText)
                Text(card.autoDetects
                     ? tr(locale, "已复制。去 Claude Code 或 Codex 里发出去，用完回来点「检查一下」。",
                          "Copied. Send it in Claude Code or Codex, then come back and tap “Check”.")
                     : tr(locale, "已复制。去 Claude Code 或 Codex 里试一次，学会了回来点「我学会了」。",
                          "Copied. Try it in Claude Code or Codex, then tap “I've got it”."))
                    .font(Theme.body).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if card.autoDetects {
                    Button { store.recheck() } label: { Label(tr(locale, "检查一下", "Check"), systemImage: "arrow.clockwise") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(store.isRefreshing)
                } else {
                    Button { store.markTried(card) } label: { Label(tr(locale, "我学会了", "I've got it"), systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(store.isRefreshing)
                }
                CopyButton(prompt: card.prompt, title: tr(locale, "再复制", "Copy again"), locale: locale)
            }
        }
    }

    private var done: some View {
        HStack(spacing: 10) {
            Text(tr(locale, "今天这一招已点亮", "Today's skill is lit"))
                .font(Theme.bodyStrong).foregroundStyle(Theme.goodText)
            Spacer()
            Button { open(.path) } label: {
                HStack(spacing: 2) {
                    Text(tr(locale, "看下一招", "Next skill"))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
            }.buttonStyle(LinkButtonStyle(color: Theme.goodText))
        }
    }

    @ViewBuilder
    private var secondaryAction: some View {
        if card.autoDetects {
            Button(tr(locale, "已用过", "Used it")) { store.recheck() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(store.isRefreshing)
                .help(tr(locale, "重新读取日志，看看有没有点亮", "Re-read your logs to see if it lit up"))
        } else {
            Button(tr(locale, "我学会了", "I've got it")) { store.markTried(card) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(store.isRefreshing)
        }
    }
}

import SwiftUI

struct HomePage: View {
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void

    var body: some View {
        VStack(spacing: Theme.gap) {
            if let snapshot = store.snapshot {
                HeroCard(snapshot: snapshot, store: store, locale: locale, open: open)
                if let card = snapshot.book?.today {
                    TodayCard(card: card, book: snapshot.book, store: store, locale: locale, open: open)
                }
                WeekCard(summary: WeekSummary(snapshot: snapshot), usage: snapshot.usageSummary, locale: locale)
                if let dimensions = snapshot.dimensions, snapshot.hasEvaluableScores {
                    DimensionsCard(dimensions: dimensions, store: store, locale: locale, open: open)
                }
                MoreCard(snapshot: snapshot, store: store, locale: locale, open: open)
            } else {
                LoadingCard(error: store.lastError, locale: locale) { store.recheck() }
            }
        }
    }
}

struct HeroCard: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ScoreRing(score: snapshot.hasEvaluableScores ? snapshot.overall?.score : nil, size: 84, line: 8)
            VStack(alignment: .leading, spacing: 6) {
                if snapshot.hasEvaluableScores, let score = snapshot.overall?.score {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Rank.of(score).title(locale)).font(Theme.title)
                        if let change = store.scoreChange {
                            Text(change.caption(locale: locale)).font(Theme.captionStrong)
                                .foregroundStyle(change.delta > 0 ? Theme.goodText : Theme.lowText)
                        } else if let delta = snapshot.progressMe?.vsYesterday, delta != 0 {
                            Text(MePresentation.signed(delta)).font(Theme.captionStrong)
                                .foregroundStyle(delta > 0 ? Theme.goodText : Theme.lowText)
                                .help(tr(locale, "和昨天比", "vs yesterday"))
                        }
                    }
                    rankingLine
                    ProgressBar(value: Rank.progress(score)).padding(.top, 2)
                    Text(Rank.nextCaption(score, locale: locale)).font(Theme.caption).foregroundStyle(Theme.secondary)
                } else {
                    Text(tr(locale, "还没有可评估的记录", "Nothing to score yet")).font(Theme.headline)
                    Text(tr(locale, "先用 Claude Code 或 Codex 做点事，回来点右上角 ↻。",
                            "Use Claude Code or Codex for a bit, then tap ↻ above."))
                        .font(Theme.caption).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    @ViewBuilder
    private var rankingLine: some View {
        if store.shareAnonymousScore {
            Text(store.ranking.map { $0.caption(locale: locale) } ?? store.rankingCaption(locale: locale))
                .font(Theme.body).foregroundStyle(Theme.secondary).lineLimit(1)
        } else {
            Button { open(.settings) } label: {
                HStack(spacing: 2) {
                    Text(tr(locale, "看看你在全球排第几", "See your global rank"))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
            }.buttonStyle(LinkButtonStyle(font: Theme.body))
        }
    }
}

struct WeekCard: View {
    let summary: WeekSummary
    let usage: UsageSummary?
    let locale: String
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr(locale, "本周", "This week")).font(Theme.captionStrong).foregroundStyle(Theme.secondary)
                Spacer()
                if usage != nil {
                    Button { showDetails.toggle() } label: { Image(systemName: "info.circle") }
                        .buttonStyle(LinkButtonStyle(color: Theme.tertiary, font: Theme.caption))
                        .help(tr(locale, "这些数字怎么来的", "Where these numbers come from"))
                        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                            Text(usage?.details(locale: locale) ?? "")
                                .font(Theme.caption).padding(14).frame(width: 320).fixedSize(horizontal: false, vertical: true)
                        }
                }
            }
            HStack(alignment: .top, spacing: 0) {
                valueStat.frame(maxWidth: .infinity, alignment: .leading)
                divider
                quotaStat.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                divider
                streakStat.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
            }
        }
        .card()
    }

    private var divider: some View { Rectangle().fill(Theme.separator).frame(width: 1, height: 44) }

    @ViewBuilder
    private var valueStat: some View {
        if let value = summary.valueUSD {
            stat(WeekSummary.money(value), tr(locale, summary.valueIsPartial ? "部分折算" : "按 API 价折算",
                                             summary.valueIsPartial ? "Partial API value" : "API-equivalent"))
        } else if let tokens = summary.tokens {
            stat(UsageSummary.tokens(tokens, locale: locale), tr(locale, "tokens", "tokens"))
        } else {
            stat("—", tr(locale, "暂无用量", "No usage yet"))
        }
    }

    @ViewBuilder
    private var quotaStat: some View {
        if let left = summary.quotaLeft {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Int(left.rounded()))%").font(Theme.number(20)).monospacedDigit().lineLimit(1)
                Text(tr(locale, "Codex 额度剩余", "Codex quota left")).font(Theme.caption).foregroundStyle(Theme.secondary)
                if let pace = summary.pace {
                    HStack(spacing: 4) {
                        Circle().fill(pace.tone.fill).frame(width: 6, height: 6)
                        Text(pace.title(locale)).foregroundStyle(pace.tone.text)
                    }.font(Theme.captionStrong)
                }
                if let reset = summary.resetsAt {
                    Text(WeekSummary.resetCaption(reset, now: Date(), locale: locale))
                        .font(Theme.caption).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
            }
        } else if let tokens = summary.tokens, summary.valueUSD != nil {
            stat(UsageSummary.tokens(tokens, locale: locale), tr(locale, "tokens（不含缓存）", "tokens, no cache"))
        } else {
            stat("—", tr(locale, "额度未知", "Quota unknown"))
        }
    }

    private var streakStat: some View {
        stat(summary.streakDays.map { tr(locale, "\($0) 天", "\($0)d") } ?? "—", tr(locale, "连续在用 AI", "Daily streak"))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(Theme.number(20)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(2)
        }
    }
}

struct DimensionsCard: View {
    let dimensions: [Dimension]
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: tr(locale, "四项能力", "Four skills"), detail: tr(locale, "点开看怎么提分", "Tap to improve"))
            VStack(spacing: 0) {
                ForEach(Array(dimensions.enumerated()), id: \.element.id) { index, dimension in
                    if index > 0 { Hairline() }
                    DimensionRow(dimension: dimension, caption: store.features.dimensionCaption(store.ranking, key: dimension.key, locale: locale),
                                 locale: locale) { open(.dimension(dimension.key)) }
                }
            }
            .card(padding: 0)
        }
    }
}

struct DimensionRow: View {
    let dimension: Dimension
    var caption: String? = nil
    let locale: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(DimensionCopy.name(dimension, locale: locale)).font(Theme.body)
                    if let score = dimension.score {
                        let state = DimensionState(score: score)
                        Chip(text: state.title(locale), tone: state.tone)
                    }
                    Spacer(minLength: 4)
                    if let caption { Text(caption).font(Theme.caption).foregroundStyle(Theme.secondary) }
                    Text(dimension.score.map(String.init) ?? "—").font(Theme.number(15)).monospacedDigit()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary)
                }
                ProgressBar(value: Double(dimension.score ?? 0) / 100,
                            tone: dimension.score.map { DimensionState(score: $0).tone } ?? .neutral, height: 4)
            }
            .padding(.horizontal, Theme.cardPadding).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DimensionCopy.name(dimension, locale: locale))
        .accessibilityValue(dimension.score.map(String.init) ?? "—")
    }
}

struct MoreCard: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let book = snapshot.book {
                NavRow(icon: "map", title: tr(locale, "修炼路线", "Your path"),
                       detail: tr(locale, "已点亮 \(book.lit) / \(book.total)", "\(book.lit) of \(book.total) lit")) { open(.path) }
                Hairline()
            }
            NavRow(icon: "flame", title: tr(locale, "今日新榜", "Trending today"), detail: trendingDetail) { open(.discover) }
            Hairline()
            NavRow(icon: "chart.line.uptrend.xyaxis", title: tr(locale, "本周复盘", "Weekly review"),
                   badge: store.features.weeklyReview ? nil : AnyView(ProLock())) { open(.weekly) }
        }
        .padding(.horizontal, Theme.cardPadding).padding(.vertical, 2)
        .card(padding: 0)
    }

    private var trendingDetail: String? {
        guard let top = snapshot.rankings?.skill?.first else { return nil }
        let name = DiscoverContent.shortName(top, in: snapshot.rankings?.skill ?? [])
        if let weekly = top.stars7d, weekly > 0 {
            return name + " +" + weekly.formatted(.number.locale(Locale(identifier: "en_US"))) + "★"
        }
        return name
    }
}

struct LoadingCard: View {
    let error: String?
    let locale: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if error == nil {
                ProgressView().controlSize(.small)
                Text(tr(locale, "正在读取本机记录…", "Reading local records…")).foregroundStyle(Theme.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 20)).foregroundStyle(Theme.lowText)
                Text(tr(locale, "这次没读成功", "Couldn't read your records")).font(Theme.headline)
                Button(tr(locale, "再试一次", "Try again"), action: retry).buttonStyle(PrimaryButtonStyle(expand: false))
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .card()
    }
}

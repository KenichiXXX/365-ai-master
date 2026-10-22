import SwiftUI
import Charts

struct DimensionPage: View {
    let dimension: Dimension
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void

    private var state: DimensionState? { dimension.score.map(DimensionState.init(score:)) }
    private var isWeakest: Bool { DiscoverContent.weakest(snapshot) == dimension.key }

    var body: some View {
        VStack(spacing: Theme.gap) {
            summary
            if isWeakest, let tip = snapshot.todayTip { quickWin(tip) }
            why
            if !(isWeakest && snapshot.todayTip != nil) { improve }
            trend
            if let limitation = dimension.evidence?.compactMap(\.limitation).first {
                Text(limitation).font(Theme.caption).foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            ScoreRing(score: dimension.score, size: 72, line: 7, tone: state?.tone ?? .neutral)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(DimensionCopy.name(dimension, locale: locale)).font(Theme.title)
                    if let state { Chip(text: state.title(locale), tone: state.tone) }
                }
                Text(DimensionCopy.blurb(dimension.key, locale: locale))
                    .font(Theme.body).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.card()
    }

    private func quickWin(_ tip: Tip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(tr(locale, "最快的提分动作", "Fastest way up"), systemImage: "bolt.fill")
                .font(Theme.captionStrong).foregroundStyle(Theme.goldText)
            Text(tip.title).font(Theme.headline)
            Text(tip.why).font(Theme.body).foregroundStyle(Theme.secondary)
            ForEach(Array(tip.steps.prefix(3).enumerated()), id: \.offset) { index, step in
                StepRow(number: index + 1, text: step, fill: Theme.surface)
            }
            if !tip.promptForClaude.isEmpty {
                CopyButton(prompt: tip.promptForClaude, title: tr(locale, "复制提示词", "Copy prompt"), locale: locale,
                           onCopied: { if let id = tip.actionId { store.practice(id: id, operation: "copy") } }, primary: true)
            }
        }.card(fill: Theme.goldSoft, stroke: Theme.gold.opacity(0.35))
    }

    private var why: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: tr(locale, "为什么是这个分", "Why this score"))
            VStack(spacing: 0) {
                let rows = (dimension.evidence ?? []).filter { $0.label != nil }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Hairline() }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label ?? "").font(Theme.body)
                            if let days = row.windowDays {
                                Text(tr(locale, "近 \(days) 天", "Last \(days) days")).font(Theme.caption).foregroundStyle(Theme.tertiary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(row.value ?? "—").font(Theme.number(15)).monospacedDigit()
                            if let target = row.target {
                                Text(tr(locale, "目标 ", "Target ") + target).font(Theme.caption).foregroundStyle(Theme.tertiary)
                            }
                        }
                    }.padding(.vertical, 9)
                }
                let deductions = dimension.deductions ?? []
                if !deductions.isEmpty { Hairline() }
                ForEach(Array(deductions.enumerated()), id: \.offset) { _, deduction in
                    HStack {
                        Image(systemName: "minus.circle.fill").foregroundStyle(Theme.low)
                        Text(deduction.title).font(Theme.body)
                        Spacer()
                        Text("−\(deduction.points)").font(Theme.number(13)).foregroundStyle(Theme.lowText)
                    }.padding(.vertical, 6)
                }
                if deductions.isEmpty, dimension.score != nil {
                    Label(tr(locale, "没有扣分，保持住", "No deductions. Keep it up"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.goodText).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Theme.cardPadding).padding(.vertical, 2)
            .card(padding: 0)
        }
    }

    @ViewBuilder
    private var improve: some View {
        let steps = dimension.steps ?? []
        if !steps.isEmpty || dimension.prompt?.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: tr(locale, "怎么提分", "How to improve"))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.prefix(3).enumerated()), id: \.offset) { index, step in
                        StepRow(number: index + 1, text: step)
                    }
                    if let prompt = dimension.prompt, !prompt.isEmpty {
                        CopyButton(prompt: prompt, title: tr(locale, "复制练习提示词", "Copy practice prompt"), locale: locale)
                    }
                }.card()
            }
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: tr(locale, "趋势与排名", "Trend and rank"))
            VStack(alignment: .leading, spacing: 10) {
                if store.features.growthCurve {
                    if let growth = snapshot.growth?.forDimension(dimension.key), TrendChart.drawable(growth) {
                        TrendChart(growth: growth, tone: state?.tone ?? .gold).frame(height: 90)
                    } else {
                        Text(tr(locale, "记录还在积累，过几天再来看", "Still collecting. Check back in a few days"))
                            .font(Theme.body).foregroundStyle(Theme.secondary)
                    }
                    if let caption = store.features.dimensionCaption(store.ranking, key: dimension.key, locale: locale) {
                        Label(caption, systemImage: "globe.asia.australia").font(Theme.body)
                    }
                } else {
                    Button { open(.pro) } label: {
                        HStack {
                            Text(tr(locale, "30 天趋势和全球排名", "30-day trend and global rank")).font(Theme.body)
                            Spacer()
                            ProLock()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.card()
        }
    }
}

struct TrendChart: View {
    let growth: Growth
    var tone: Tone = .gold

    var body: some View {
        let segments = growth.segments
        Chart {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                ForEach(segment) { day in
                    if let date = Self.date(day.date), let score = day.score {
                        LineMark(x: .value("day", date), y: .value("score", score), series: .value("segment", index))
                            .foregroundStyle(tone.fill)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        PointMark(x: .value("day", date), y: .value("score", score))
                            .foregroundStyle(tone.fill).symbolSize(segment.count == 1 ? 30 : 0)
                    }
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: Self.domain(growth))
        .chartYAxis { AxisMarks(values: [0, 50, 100]) { AxisGridLine().foregroundStyle(Theme.hairline); AxisValueLabel() } }
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { AxisValueLabel(format: .dateTime.month(.defaultDigits).day()) } }
        .font(Theme.caption)
    }

    static func drawable(_ growth: Growth) -> Bool { growth.days.filter { $0.score != nil }.count >= 2 }

    static func domain(_ growth: Growth) -> ClosedRange<Date> {
        let dates = growth.days.compactMap { date($0.date) }
        guard let first = dates.min(), let last = dates.max(), first < last else {
            let now = Date()
            return now.addingTimeInterval(-29 * 86400)...now
        }
        return first...last
    }

    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

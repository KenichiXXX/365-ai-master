import SwiftUI

struct WeeklyPage: View {
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void

    var body: some View {
        VStack(spacing: Theme.gap) {
            if store.features.weeklyReview, let snapshot = store.snapshot {
                if let weekly = snapshot.weekly { review(weekly, snapshot: snapshot) }
                curve(snapshot)
                Button { open(.share) } label: { Label(tr(locale, "分享我的段位", "Share my rank"), systemImage: "square.and.arrow.up") }
                    .buttonStyle(SecondaryButtonStyle(expand: true))
            } else {
                locked
            }
        }
    }

    private func review(_ weekly: WeeklyReview, snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr(locale, "\(DisplayDate.short(weekly.weekStart, locale: locale)) 起的一周", "Week of \(DisplayDate.short(weekly.weekStart, locale: locale))"))
                .font(Theme.captionStrong).foregroundStyle(Theme.secondary)
            HStack(spacing: 0) {
                metric("\(weekly.daysActive)", tr(locale, "天在用 AI", "active days"))
                metric("\(weekly.cardsLitThisWeek.count)", tr(locale, "招新点亮", "skills lit"))
                metric(weekly.scoreDelta.map { String(format: "%+.1f", $0) } ?? "—", tr(locale, "分数变化", "score change"))
            }
            if let change = weekly.observedChange?.text { line("eye", change) }
            if let uncertainty = weekly.uncertainty?.text { line("hourglass", uncertainty) }
            if let next = weekly.nextPractice {
                let title = next.practiceId.flatMap { id in snapshot.book?.cards.first { $0.id == id }?.title }
                line("arrow.forward.circle", tr(locale, "下周练：", "Next week: ") + (title ?? next.text))
            }
        }.card()
    }

    private func curve(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: tr(locale, "30 天分数", "30-day score"),
                          detail: snapshot.progressMe?.personalBest.map { tr(locale, "个人最佳 \($0)", "Best \($0)") })
            Group {
                if let growth = snapshot.growth, TrendChart.drawable(growth) {
                    TrendChart(growth: growth).frame(height: 120)
                } else {
                    Text(snapshot.overall?.score.map { tr(locale, "今天 \($0) 分。再记录一两天，曲线就出来了。", "\($0) today. A day or two more and the curve appears.") }
                         ?? tr(locale, "记录还在积累，过几天再来看", "Still collecting. Check back in a few days"))
                        .font(Theme.body).foregroundStyle(Theme.secondary)
                }
            }.card()
        }
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.goldText)
            Text(tr(locale, "每周一份复盘", "A review every week")).font(Theme.title)
            VStack(alignment: .leading, spacing: 6) {
                bullet(tr(locale, "这周分数涨了还是跌了，为什么", "How your score moved, and why"))
                bullet(tr(locale, "学会了哪几招，哪几招在反复用", "Which skills you learned and keep reusing"))
                bullet(tr(locale, "下周最该练的一招", "The one skill to practise next week"))
                bullet(tr(locale, "30 天成长曲线", "Your 30-day growth curve"))
            }
            Button(tr(locale, "了解 Pro", "See Pro")) { open(.pro) }.buttonStyle(PrimaryButtonStyle())
        }.card()
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.number(22)).monospacedDigit()
            Text(label).font(Theme.caption).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(Theme.goldText).frame(width: 16)
            Text(text).font(Theme.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ text: String) -> some View {
        Label(text, systemImage: "checkmark").font(Theme.body).labelStyle(BulletLabelStyle())
    }
}

struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.goldText)
            configuration.title
        }
    }
}

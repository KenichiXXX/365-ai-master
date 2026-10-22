import SwiftUI
import Charts

struct GrowthCurve: View {
    let growth: Growth
    let zh: Bool

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.grid) {
                Text(zh ? "成长曲线" : "Growth curve").font(Theme.title)
                Chart {
                    ForEach(Array(growth.segments.enumerated()), id: \.offset) { index, segment in
                        ForEach(segment) { day in
                            if let score = day.score {
                                LineMark(x: .value(zh ? "日期" : "Date", day.date),
                                         y: .value(zh ? "分数" : "Score", score),
                                         series: .value("Segment", String(index)))
                                .foregroundStyle(Theme.ink)
                                PointMark(x: .value(zh ? "日期" : "Date", day.date),
                                          y: .value(zh ? "分数" : "Score", score))
                                .foregroundStyle(Theme.ink)
                            }
                        }
                    }
                }
                .chartXScale(domain: growth.days.map(\.date))
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel().font(Theme.label).foregroundStyle(Theme.secondary)
                        AxisGridLine().foregroundStyle(Theme.ink)
                    }
                }
                .frame(height: 130)
                HStack {
                    Text(DisplayDate.short(growth.days.first?.date ?? "", locale: zh ? "zh" : "en"))
                    Spacer()
                    Text(DisplayDate.short(growth.days.last?.date ?? "", locale: zh ? "zh" : "en"))
                }.font(Theme.label).foregroundStyle(Theme.secondary)
                if let delta = growth.comparableDelta {
                    let signed = String(format: "%+.2f", delta)
                    HStack(spacing: Theme.grid) {
                        TrendMarker(delta: delta)
                        Text(zh ? "同星期窗口均分变化 \(signed) 分" : "Mean score change for matched weekdays: \(signed) points")
                    }
                } else {
                    Text(zh ? "可比数据积累中" : "Collecting comparable data").foregroundStyle(Theme.secondary)
                    if growth.comparison?.reason == "version_changed" {
                        Text(zh ? "评分版本变化" : "Scoring version changed").font(Theme.label)
                    }
                }
            }
        }.bauhausTheme()
    }
}

struct WeeklyReviewSheet: View {
    let snapshot: Snapshot
    @Environment(\.dismiss) private var dismiss
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.grid) {
                    Text(zh ? "本周复盘" : "Weekly review").font(Theme.title)
                    if let weekly = snapshot.weekly {
                        Text(DisplayDate.short(weekly.weekStart, locale: snapshot.locale ?? "en")).foregroundStyle(Theme.secondary)
                        Text(weekly.summary(locale: snapshot.locale ?? "en"))
                        if let observed = weekly.observedChange {
                            Text(observed.text).font(Theme.title)
                            Text(([observed.metricId].compactMap { $0 } + (observed.evidenceIds ?? [])).joined(separator: " · "))
                                .font(Theme.label).foregroundStyle(Theme.secondary)
                        }
                        if let uncertainty = weekly.uncertainty { Text(uncertainty.text).foregroundStyle(Theme.secondary) }
                        Text(zh ? "配置 / 自报：\(weekly.configurationIds?.count ?? 0) / \(weekly.selfReportIds?.count ?? 0)；复用：\(weekly.reuseEvidenceIds?.count ?? 0)"
                             : "Configuration / self-report: \(weekly.configurationIds?.count ?? 0) / \(weekly.selfReportIds?.count ?? 0); reuse: \(weekly.reuseEvidenceIds?.count ?? 0)")
                        if let next = weekly.nextPractice {
                            Text(next.text).font(Theme.title)
                            Text(snapshot.book?.cards.first { $0.id == next.practiceId }?.title ?? next.practiceId ?? "")
                        }
                        if let report = weekly.reportText {
                            CopyButton(prompt: report, title: zh ? "复制复盘" : "Copy review", locale: snapshot.locale ?? "en")
                        }
                    } else {
                        Text(zh ? "暂无周报数据" : "No weekly data yet")
                    }
                    Button(zh ? "完成" : "Done") { dismiss() }
                }.padding(Theme.grid * 2).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 400, height: 480)
        }.bauhausTheme()
    }
}

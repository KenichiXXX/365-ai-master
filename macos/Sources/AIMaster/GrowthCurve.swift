import SwiftUI
import Charts

struct GrowthCurve: View {
    let growth: Growth
    let zh: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(zh ? "成长曲线" : "Growth curve").font(.headline)
            Chart {
                ForEach(Array(growth.segments.enumerated()), id: \.offset) { index, segment in
                    ForEach(segment) { day in
                        if let score = day.score {
                            LineMark(x: .value(zh ? "日期" : "Date", day.date),
                                     y: .value(zh ? "分数" : "Score", score),
                                     series: .value("Segment", String(index)))
                            PointMark(x: .value(zh ? "日期" : "Date", day.date),
                                      y: .value(zh ? "分数" : "Score", score))
                        }
                    }
                }
            }
            .chartXScale(domain: growth.days.map(\.date))
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .frame(height: 130)
            HStack {
                Text(growth.days.first?.date ?? "")
                Spacer()
                Text(growth.days.last?.date ?? "")
            }.font(.caption).foregroundStyle(.secondary)
            if let delta = growth.comparableDelta {
                let signed = String(format: "%+.2f", delta)
                Text(zh ? "同星期窗口均分变化 \(signed) 分" : "Mean score change for matched weekdays: \(signed) points")
            } else {
                Text(zh ? "可比数据积累中" : "Collecting comparable data").foregroundStyle(.secondary)
                if growth.comparison?.reason == "version_changed" {
                    Text(zh ? "评分版本变化" : "Scoring version changed").font(.caption)
                }
            }
        }
    }
}

struct WeeklyReviewSheet: View {
    let snapshot: Snapshot
    @Environment(\.dismiss) private var dismiss
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(zh ? "本周复盘" : "Weekly review").font(.title2.bold())
                if let weekly = snapshot.weekly {
                    Text(weekly.weekStart).foregroundStyle(.secondary)
                    Text(weekly.summary(locale: snapshot.locale ?? "en"))
                    if let observed = weekly.observedChange {
                        Text(observed.text).font(.headline)
                        Text(([observed.metricId].compactMap { $0 } + (observed.evidenceIds ?? [])).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let uncertainty = weekly.uncertainty { Text(uncertainty.text).foregroundStyle(.secondary) }
                    Text(zh ? "配置 / 自报：\(weekly.configurationIds?.count ?? 0) / \(weekly.selfReportIds?.count ?? 0)；复用：\(weekly.reuseEvidenceIds?.count ?? 0)"
                         : "Configuration / self-report: \(weekly.configurationIds?.count ?? 0) / \(weekly.selfReportIds?.count ?? 0); reuse: \(weekly.reuseEvidenceIds?.count ?? 0)")
                    if let next = weekly.nextPractice {
                        Text(next.text).font(.headline)
                        Text(snapshot.book?.cards.first { $0.id == next.practiceId }?.title ?? next.practiceId ?? "")
                    }
                    if let report = weekly.reportText {
                        CopyButton(prompt: report, title: zh ? "复制复盘" : "Copy review", locale: snapshot.locale ?? "en")
                    }
                } else {
                    Text(zh ? "暂无周报数据" : "No weekly data yet")
                }
                Button(zh ? "完成" : "Done") { dismiss() }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: 400, height: 480)
    }
}

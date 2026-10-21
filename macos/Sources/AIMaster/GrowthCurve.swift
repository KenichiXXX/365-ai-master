import SwiftUI
import Charts

struct GrowthCurve: View {
    let growth: Growth
    let zh: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(zh ? "成长曲线" : "Growth curve").font(.headline)
            Chart(growth.days) { day in
                LineMark(x: .value(zh ? "日期" : "Date", day.date),
                         y: .value(zh ? "分数" : "Score", day.score))
                PointMark(x: .value(zh ? "日期" : "Date", day.date),
                          y: .value(zh ? "分数" : "Score", day.score))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .frame(height: 130)
            HStack {
                Text(growth.days.first?.date ?? "")
                Spacer()
                Text(growth.days.last?.date ?? "")
            }.font(.caption).foregroundStyle(.secondary)
            if let delta = growth.weekDelta {
                let signed = delta >= 0 ? "+\(delta)" : String(delta)
                Text(zh ? "本周比上周 \(signed)" : "This week vs last week \(signed)")
            } else {
                Text(zh ? "暂无上周数据" : "No data last week").foregroundStyle(.secondary)
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
                    Text(zh ? "本周点亮的技能" : "Skills lit this week").font(.headline)
                    if weekly.cardsLitThisWeek.isEmpty { Text(zh ? "暂无" : "None yet") }
                    ForEach(weekly.cardsLitThisWeek, id: \.self) { id in
                        Text("✓ " + (snapshot.book?.cards.first { $0.id == id }?.title ?? id))
                    }
                    Text(zh ? "本周通过的关卡" : "Quests passed this week").font(.headline)
                    if weekly.questsPassedThisWeek.isEmpty { Text(zh ? "暂无" : "None yet") }
                    ForEach(weekly.questsPassedThisWeek, id: \.self) { key in
                        Text("✓ " + (snapshot.village?.quests.first { $0.key == key }?.title ?? key))
                    }
                } else {
                    Text(zh ? "暂无周报数据" : "No weekly data yet")
                }
                Button(zh ? "完成" : "Done") { dismiss() }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: 400, height: 480)
    }
}

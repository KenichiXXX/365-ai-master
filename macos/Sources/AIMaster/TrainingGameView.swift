import SwiftUI

struct TrainingGameView: View {
    let game: TrainingGame
    @ObservedObject var store: SnapshotStore
    let zh: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("selectedTab") private var selectedTab = 0
    @State private var stampScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button {
                    store.checkIn()
                } label: {
                    Label(game.today.checkin ? (zh ? "今日已打卡 ✓" : "Checked in today ✓")
                          : (zh ? "今天打卡 · +5 XP" : "Check in · +5 XP"), systemImage: "checkmark.seal.fill")
                        .scaleEffect(stampScale)
                }.disabled(game.today.checkin || store.isRefreshing)
                Spacer()
                Label("\(game.shields)", systemImage: "shield.fill")
                    .accessibilityLabel(zh ? "连签保护卡 \(game.shields) 张" : "\(game.shields) streak shields")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(zh ? "今日三件事" : "Today's 3").font(.headline)
                    Spacer()
                    Text("\(game.today.completed)/3").monospacedDigit()
                }
                dailyRow(zh ? "打卡" : "Check in", done: game.today.checkin)
                Button { selectedTab = 1 } label: {
                    dailyRow(zh ? "看一张卡" : "Read a card", done: game.today.cardRead)
                }.buttonStyle(.plain).foregroundStyle(.tint)
                dailyRow(zh ? "练一次" : "Practise once", done: game.today.practice)
                if let tip = game.today.chestTip {
                    Label(zh ? "今日宝箱 · +20 XP" : "Daily chest · +20 XP", systemImage: "gift.fill")
                        .foregroundStyle(.tint)
                    Text(tip).font(.body)
                }
                DisclosureGroup {
                    Text(zh ? "完成三件事，开启今日宝箱 · +20 XP" : "Finish all three to open your daily chest · +20 XP")
                        .font(.body)
                } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "宝箱说明" : "Chest details") }
            }.padding(10).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("Lv.\(game.level) · \(game.levelTitle)").font(.headline)
                Spacer()
                Text("\(game.levelXp)/\(game.nextLevelXp)").monospacedDigit()
            }.accessibilityLabel(zh ? "经验与等级，等级 \(game.level)，\(game.levelTitle)" : "XP and level, level \(game.level), \(game.levelTitle)")
            ProgressView(value: Double(game.levelXp), total: Double(max(1, game.nextLevelXp)))
            DisclosureGroup(zh ? "经验来源 · 共 \(game.xp) XP" : "XP rewards · \(game.xp) XP total") {
                Text(zh ? "打卡 +5 · 读卡 +5 · 练习 +20 · 关卡 +50 · 徽章 +30 · 宝箱 +20 · 每周挑战 +50"
                     : "Check-in +5 · Read +5 · Practice +20 · Quest +50 · Badge +30 · Chest +20 · Weekly challenge +50")
                    .font(.body)
            }
            calendar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(zh ? "每周挑战" : "Weekly challenge").font(.headline)
                    Spacer()
                    Text("\(game.weekly.have)/\(game.weekly.need)").monospacedDigit()
                }
                Text(game.weekly.title)
                ProgressView(value: Double(game.weekly.have), total: Double(max(1, game.weekly.need)))
                if game.weekly.earned { Label("+50 XP ✓", systemImage: "rosette").font(.body) }
                DisclosureGroup {
                    Text(zh ? "完成可获 +50 XP 和每周徽章" : "Earn +50 XP and a weekly badge")
                        .font(.body)
                } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "挑战奖励" : "Challenge reward") }
                if !game.weeklyBadges.isEmpty {
                    DisclosureGroup(zh ? "每周徽章 · \(game.weeklyBadges.count)" : "Weekly badges · \(game.weeklyBadges.count)") {
                        ForEach(game.weeklyBadges, id: \.self) { badge in
                            Label(badge.replacingOccurrences(of: "weekly:", with: ""), systemImage: "rosette")
                        }
                    }
                }
            }
        }
        .onChange(of: game.today.checkin) { stamped in
            guard stamped, !reduceMotion else { return }
            stampScale = 1.2
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { stampScale = 1 }
        }
    }

    private func dailyRow(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle").font(.body)
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((zh ? "打卡日历 · " : "Check-in calendar · ") + game.month).font(.headline)
            Text(zh ? "连签 \(game.streak) 天 · 最佳 \(game.bestStreak) 天"
                 : "Streak \(game.streak) days · Best \(game.bestStreak) days")
                .font(.body).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array((zh ? ["一", "二", "三", "四", "五", "六", "日"]
                               : ["M", "T", "W", "T", "F", "S", "S"]).enumerated()), id: \.offset) { _, name in
                    Text(name).font(.body).foregroundStyle(.secondary)
                }
                ForEach(0..<game.firstWeekday, id: \.self) { _ in Color.clear.frame(height: 24) }
                ForEach(game.calendar) { day in
                    HStack(spacing: 1) {
                        Text(String(Int(day.date.suffix(2)) ?? 0))
                        if day.state == "stamp" { Image(systemName: "checkmark.seal.fill") }
                        if day.state == "shield" { Image(systemName: "shield.fill") }
                    }.font(.body).frame(maxWidth: .infinity, minHeight: 24)
                        .background(day.state == "empty" ? Color.secondary.opacity(0.04) : Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel(day.date + ", " + (day.state == "stamp" ? (zh ? "已打卡" : "Checked in")
                            : day.state == "shield" ? (zh ? "保护卡" : "Shield") : (zh ? "未打卡" : "No check-in")))
                }
            }
            DisclosureGroup {
                Text(zh ? "每连签 7 天获 1 张保护卡，最多 2 张；漏签时自动使用。"
                 : "Earn a shield every 7-day streak, up to 2. Used automatically for missed days.")
                    .font(.body)
            } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "保护卡说明" : "Shield details") }
        }
    }
}

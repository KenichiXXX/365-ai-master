import SwiftUI

struct TrainingGameView: View {
    let game: TrainingGame
    @ObservedObject var store: SnapshotStore
    let zh: Bool
    var openToday: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stampScale: CGFloat = 1

    static func stampScale(checkedIn: Bool, reduceMotion: Bool) -> CGFloat {
        checkedIn && !reduceMotion ? 1.12 : 1
    }

    var body: some View {
        VStack(spacing: Theme.sectionGap) {
            Button(action: openToday) {
                VStack(spacing: Theme.cardPadding) {
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.grid * 2) {
                            Text(zh ? "今日修炼" : "Today's training").font(Theme.title)
                            Text(zh ? "连签 \(game.streak) 天" : "\(game.streak)-day streak")
                                .font(Theme.label).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: Theme.grid) {
                            Text("\(game.today.completed)").font(Theme.stat).foregroundStyle(Theme.accent)
                            Text("/ 3").font(Theme.label).foregroundStyle(Theme.secondary)
                        }
                    }
                    HStack(spacing: Theme.grid * 2) {
                        ForEach(0..<3) { index in
                            Capsule().fill(index < game.today.completed ? Theme.accent : Theme.hairline)
                                .frame(height: Theme.grid)
                        }
                    }.accessibilityHidden(true)
                }.padding(Theme.cardPadding).bauhausPanel()
            }.buttonStyle(.plain).accessibilityIdentifier("training-today")
                .accessibilityLabel(zh ? "今日修炼" : "Today's training")
                .accessibilityValue("\(game.today.completed)/3")
            VStack(spacing: Theme.cardPadding) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Lv.\(game.level)").font(Theme.stat)
                    Spacer()
                    Text("\(game.levelXp) / \(game.nextLevelXp) XP")
                        .font(Theme.label).foregroundStyle(Theme.secondary)
                }
                ProgressView(value: Double(game.levelXp), total: Double(max(1, game.nextLevelXp)))
                    .accessibilityLabel(zh ? "等级经验" : "Level XP")
                    .accessibilityValue("\(game.levelXp)/\(game.nextLevelXp) XP")
                Button { store.checkIn() } label: {
                    Text(game.today.checkin ? (zh ? "已打卡 ✓ 明天见" : "Checked in ✓ See you tomorrow")
                         : (zh ? "打卡 +5 XP" : "Check in +5 XP"))
                        .scaleEffect(stampScale).frame(maxWidth: .infinity)
                }.buttonStyle(ThemeButtonStyle(primary: !game.today.checkin))
                    .disabled(game.today.checkin || store.isRefreshing)
                    .accessibilityIdentifier("training-checkin")
                    .onChange(of: game.today.checkin) { checkedIn in
                        let peak = Self.stampScale(checkedIn: checkedIn, reduceMotion: reduceMotion)
                        guard peak != 1 else { stampScale = 1; return }
                        stampScale = peak
                        withAnimation(.easeOut(duration: Theme.feedbackDuration)) { stampScale = 1 }
                    }
            }.padding(Theme.cardPadding).bauhausPanel()
        }.monospacedDigit()
    }
}


struct TrainingGameDetailView: View {
    let game: TrainingGame
    @ObservedObject var store: SnapshotStore
    let zh: Bool
    let destination: TrainingDestination
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedTab") private var selectedTab = 0
    @State private var stampScale: CGFloat = 1

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                if destination == .today {
                    ThemeLabel(zh ? "今日修炼" : "Today's training")
                    HStack {
                        Button {
                            store.checkIn()
                        } label: {
                            Label(game.today.checkin ? (zh ? "今日已打卡 ✓" : "Checked in today ✓")
                                  : (zh ? "今天打卡 · +5 XP" : "Check in · +5 XP"), systemImage: "checkmark.seal.fill")
                                .scaleEffect(stampScale)
                        }.buttonStyle(ThemeButtonStyle(primary: !game.today.checkin))
                            .disabled(game.today.checkin || store.isRefreshing)
                        Spacer()
                        Label("\(game.shields)", systemImage: "shield.fill")
                            .accessibilityLabel(zh ? "连签保护卡 \(game.shields) 张" : "\(game.shields) streak shields")
                    }
                    VStack(alignment: .leading, spacing: Theme.grid) {
                        HStack {
                            Text(zh ? "今日三件事" : "Today's 3").font(Theme.title)
                            Spacer()
                            Text("\(game.today.completed)/3").monospacedDigit()
                        }
                        dailyRow(zh ? "打卡" : "Check in", done: game.today.checkin)
                        Button { selectedTab = 1; dismiss() } label: {
                            dailyRow(zh ? "看一张卡" : "Read a card", done: game.today.cardRead)
                        }.buttonStyle(.plain).foregroundStyle(Theme.ink)
                        Button { selectedTab = 1; dismiss() } label: {
                            dailyRow(zh ? "练一次" : "Practise once", done: game.today.practice)
                        }.buttonStyle(.plain)
                        if let tip = game.today.chestTip {
                            VStack(alignment: .leading, spacing: Theme.grid * 2) {
                                Label(zh ? "今日宝箱 · +20 XP" : "Daily chest · +20 XP", systemImage: "gift.fill")
                                    .foregroundStyle(Theme.accent)
                                Text(tip).font(Theme.body)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        DisclosureGroup {
                            Text(zh ? "完成三件事，开启今日宝箱 · +20 XP" : "Finish all three to open your daily chest · +20 XP")
                                .font(Theme.body)
                        } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "宝箱说明" : "Chest details") }
                    }.padding(Theme.cardPadding).bauhausPanel()
                    HStack {
                        Text("Lv.\(game.level) · \(game.levelTitle)").font(Theme.title)
                        Spacer()
                        Text("\(game.levelXp)/\(game.nextLevelXp)").monospacedDigit()
                    }.accessibilityLabel(zh ? "经验与等级，等级 \(game.level)，\(game.levelTitle)" : "XP and level, level \(game.level), \(game.levelTitle)")
                    ProgressView(value: Double(game.levelXp), total: Double(max(1, game.nextLevelXp)))
                    DisclosureGroup(zh ? "经验来源 · 共 \(game.xp) XP" : "XP rewards · \(game.xp) XP total") {
                        Text(zh ? "打卡 +5 · 读卡 +5 · 练习 +20 · 关卡 +50 · 徽章 +30 · 宝箱 +20 · 每周挑战 +50"
                             : "Check-in +5 · Read +5 · Practice +20 · Quest +50 · Badge +30 · Chest +20 · Weekly challenge +50")
                            .font(Theme.body)
                    }
                    calendar
                }
                if destination == .challenge {
                    VStack(alignment: .leading, spacing: Theme.grid) {
                        HStack {
                            Text(zh ? "每周挑战" : "Weekly challenge").font(Theme.title)
                            Spacer()
                            Text("\(game.weekly.have)/\(game.weekly.need)").monospacedDigit()
                        }
                        Text(game.weekly.title)
                        ProgressView(value: Double(game.weekly.have), total: Double(max(1, game.weekly.need)))
                        if game.weekly.earned { Label("+50 XP ✓", systemImage: "rosette").font(Theme.body) }
                        DisclosureGroup {
                            Text(zh ? "完成可获 +50 XP 和每周徽章" : "Earn +50 XP and a weekly badge")
                                .font(Theme.body)
                        } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "挑战奖励" : "Challenge reward") }
                        if !game.weeklyBadges.isEmpty {
                            DisclosureGroup(zh ? "每周徽章 · \(game.weeklyBadges.count)" : "Weekly badges · \(game.weeklyBadges.count)") {
                                ForEach(game.weeklyBadges, id: \.self) { badge in
                                    Label(badge.replacingOccurrences(of: "weekly:", with: ""), systemImage: "rosette")
                                }
                            }
                        }
                    }.padding(Theme.cardPadding).bauhausPanel()
                }
            }
            .onChange(of: game.today.checkin) { stamped in
                guard stamped, !reduceMotion else { return }
                stampScale = TrainingGameView.stampScale(checkedIn: stamped, reduceMotion: reduceMotion)
                withAnimation(.easeOut(duration: Theme.feedbackDuration)) { stampScale = 1 }
            }
        }.bauhausTheme()
    }

    private func dailyRow(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .font(Theme.body).foregroundStyle(done ? Theme.accent : Theme.secondary)
            .padding(.vertical, Theme.grid * 2)
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: Theme.grid) {
            Text((zh ? "打卡日历 · " : "Check-in calendar · ") + game.month).font(Theme.title)
            Text(zh ? "连签 \(game.streak) 天 · 最佳 \(game.bestStreak) 天"
                 : "Streak \(game.streak) days · Best \(game.bestStreak) days")
                .font(Theme.body).foregroundStyle(Theme.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.grid), count: 7), spacing: Theme.grid) {
                ForEach(Array((zh ? ["一", "二", "三", "四", "五", "六", "日"]
                               : ["M", "T", "W", "T", "F", "S", "S"]).enumerated()), id: \.offset) { _, name in
                    Text(name).font(Theme.body).foregroundStyle(Theme.secondary)
                }
                ForEach(0..<game.firstWeekday, id: \.self) { _ in Color.clear.frame(height: 24) }
                ForEach(game.calendar) { day in
                    HStack(spacing: 1) {
                        Text(String(Int(day.date.suffix(2)) ?? 0))
                        if day.state == "stamp" { Image(systemName: "checkmark.seal.fill") }
                        if day.state == "shield" { Image(systemName: "shield.fill") }
                    }.font(Theme.body).frame(maxWidth: .infinity, minHeight: 24)
                        .foregroundStyle(day.state == "empty" ? Theme.secondary : Theme.accent)
                        .background(day.state == "empty" ? Theme.hairline : Theme.accentSurface,
                                    in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                        .accessibilityLabel(day.date + ", " + (day.state == "stamp" ? (zh ? "已打卡" : "Checked in")
                            : day.state == "shield" ? (zh ? "保护卡" : "Shield") : (zh ? "未打卡" : "No check-in")))
                }
            }
            DisclosureGroup {
                Text(zh ? "每连签 7 天获 1 张保护卡，最多 2 张；漏签时自动使用。"
                 : "Earn a shield every 7-day streak, up to 2. Used automatically for missed days.")
                    .font(Theme.body)
            } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "保护卡说明" : "Shield details") }
        }
    }
}

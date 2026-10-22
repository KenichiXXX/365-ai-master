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
        VStack(spacing: Theme.grid * 2) {
            HStack(spacing: Theme.grid * 2) {
                Button(action: openToday) {
                    ZStack {
                        Circle().stroke(Theme.hairline, lineWidth: Theme.grid)
                        Circle().trim(from: 0, to: CGFloat(min(3, max(0, game.today.completed))) / 3)
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: Theme.grid, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                        Text("\(game.today.completed)/3").font(Theme.title).monospacedDigit()
                            .foregroundStyle(Theme.accent)
                    }.frame(width: Theme.grid * 9, height: Theme.grid * 9).padding(Theme.grid)
                }.buttonStyle(.plain).accessibilityIdentifier("training-today")
                    .accessibilityLabel(zh ? "今日三件事" : "Today's 3")
                    .accessibilityValue("\(game.today.completed)/3")
                VStack(alignment: .leading, spacing: Theme.grid) {
                    Text("TODAY").font(Theme.label).tracking(2)
                    Text(zh ? "今日修炼" : "Today's training").font(Theme.title)
                    Text(zh ? "连签 \(game.streak) 天 · Lv.\(game.level)"
                         : "\(game.streak)-day streak · Lv.\(game.level)").font(Theme.body)
                }.foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }.padding(Theme.grid * 2).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
            Button { store.checkIn() } label: {
                Text(game.today.checkin ? (zh ? "已打卡 ✓ 明天见" : "Checked in ✓ See you tomorrow")
                     : (zh ? "打卡 +5 XP" : "Check in +5 XP"))
                    .font(Theme.title).scaleEffect(stampScale)
                    .frame(maxWidth: .infinity).padding(Theme.grid * 2)
                    .foregroundStyle(game.today.checkin ? Theme.ink : Theme.onAccent)
                    .background(game.today.checkin ? Theme.paper : Theme.accent)
                    .overlay(Rectangle().strokeBorder(game.today.checkin ? Theme.ink : Theme.accent, lineWidth: Theme.ruleWidth))
            }.buttonStyle(.plain).disabled(game.today.checkin || store.isRefreshing)
                .accessibilityIdentifier("training-checkin")
                .onChange(of: game.today.checkin) { checkedIn in
                    let peak = Self.stampScale(checkedIn: checkedIn, reduceMotion: reduceMotion)
                    guard peak != 1 else { stampScale = 1; return }
                    withAnimation(.easeOut(duration: 0.12)) { stampScale = peak }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { stampScale = 1 }
                    }
                }
        }
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
            VStack(alignment: .leading, spacing: Theme.grid) {
                if destination == .today {
                    ThemeLabel("TODAY")
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
                            Label(zh ? "今日宝箱 · +20 XP" : "Daily chest · +20 XP", systemImage: "gift.fill")
                                .foregroundStyle(Theme.ink)
                            Text(tip).font(Theme.body)
                        }
                        DisclosureGroup {
                            Text(zh ? "完成三件事，开启今日宝箱 · +20 XP" : "Finish all three to open your daily chest · +20 XP")
                                .font(Theme.body)
                        } label: { Image(systemName: "info.circle").accessibilityLabel(zh ? "宝箱说明" : "Chest details") }
                    }.padding(Theme.grid).bauhausPanel()
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
                    }
                }
            }
            .onChange(of: game.today.checkin) { stamped in
                guard stamped, !reduceMotion else { return }
                stampScale = 1.2
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { stampScale = 1 }
            }
        }.bauhausTheme()
    }

    private func dailyRow(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle").font(Theme.body)
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
                        .foregroundStyle(Theme.ink)
                        .background(day.state == "empty" ? Theme.paper : Theme.accentSurface)
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.ruleWidth))
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

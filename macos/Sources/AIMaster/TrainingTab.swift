import SwiftUI

enum TrainingDestination: String, Identifiable, CaseIterable {
    case today, village, book, badges, challenge
    var id: String { rawValue }
    func title(zh: Bool) -> String {
        switch self {
        case .today: return zh ? "今日三件事" : "Today's 3"
        case .village: return zh ? "新手村" : "Village"
        case .book: return zh ? "图鉴" : "Skill book"
        case .badges: return zh ? "徽章" : "Badges"
        case .challenge: return zh ? "本周挑战" : "Weekly challenge"
        }
    }
}

struct TrainingTab: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    @State private var destination: TrainingDestination?
    @AppStorage("trainingAchievementLedger") private var achievementData = Data()
    @State private var moments: [TrainingMoment] = []
    private var zh: Bool { snapshot.locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            if let moment = moments.first {
                Button { moments.removeFirst() } label: {
                    Text("▲ " + moment.title(zh: zh)).font(Theme.title).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.cardPadding)
                        .foregroundStyle(Theme.accentText)
                        .background(Theme.accentSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }.buttonStyle(.plain).accessibilityIdentifier("training-achievement")
                    .task(id: moment.id) {
                        do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
                        if moments.first?.id == moment.id { moments.removeFirst() }
                    }
            }
            if let game = snapshot.trainingGame {
                TrainingGameView(game: game, store: store, zh: zh) { destination = .today }
            } else {
                Button { destination = .today } label: {
                    VStack(alignment: .leading, spacing: Theme.grid) {
                        Text(zh ? "今日修炼" : "Today's training").font(Theme.title)
                        Text(zh ? "暂无修炼记录" : "No training records yet").font(Theme.body)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(Theme.cardPadding)
                        .foregroundStyle(Theme.ink).bauhausPanel()
                }.buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                tile(.village, value: snapshot.village?.quests.filter { $0.status == "passed" }.count ?? 0, total: 9)
                Rectangle().fill(Theme.hairline).frame(width: Theme.ruleWidth, height: Theme.grid * 13)
                tile(.book, value: snapshot.book?.lit ?? 0, total: snapshot.book?.total ?? 0)
                Rectangle().fill(Theme.hairline).frame(width: Theme.ruleWidth, height: Theme.grid * 13)
                tile(.badges, value: (snapshot.badges ?? []).filter(\.earned).count + (snapshot.trainingGame?.weeklyBadges.count ?? 0))
            }.padding(Theme.cardPadding).bauhausPanel()
            if let challenge = snapshot.trainingGame?.weekly {
                Button { destination = .challenge } label: {
                    VStack(alignment: .leading, spacing: Theme.grid * 3) {
                        HStack {
                            Text(TrainingDestination.challenge.title(zh: zh)).font(Theme.label)
                            Spacer()
                            Text("\(challenge.have) / \(challenge.need)").font(Theme.label)
                        }.foregroundStyle(Theme.secondary)
                        Text(challenge.title).font(Theme.body)
                        ProgressView(value: Double(challenge.have), total: Double(max(1, challenge.need)))
                        HStack(spacing: Theme.grid * 2) {
                            ForEach(Array((zh ? ["一", "二", "三", "四", "五", "六", "日"]
                                           : ["M", "T", "W", "T", "F", "S", "S"]).enumerated()), id: \.offset) { _, day in
                                Text(day).font(Theme.label).foregroundStyle(Theme.secondary)
                                    .frame(width: Theme.grid * 6, height: Theme.grid * 6)
                                    .background(Theme.hairline, in: Circle())
                            }
                        }.accessibilityLabel(zh ? "一周七天，周一至周日" : "Seven days, Monday to Sunday")
                        Text(zh ? "每天一点，逐渐熟练。" : "A little practice, every day.")
                            .font(Theme.label).foregroundStyle(Theme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.cardPadding).bauhausPanel()
                }.buttonStyle(.plain).accessibilityIdentifier("training-challenge")
            }
        }.bauhausTheme()
            .sheet(item: $destination) { page in
                VStack(alignment: .leading, spacing: Theme.grid) {
                    HStack {
                        Text(page.title(zh: zh)).font(Theme.title)
                        Spacer()
                        Button(zh ? "完成" : "Done") { destination = nil }
                    }.padding(Theme.cardPadding)
                    ThemeRule()
                    ScrollView {
                        TrainingDetailPage(destination: page, snapshot: store.snapshot ?? snapshot, store: store)
                            .padding(Theme.pagePadding).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(width: 440, height: 560).background(MasterWindowBackground()).bauhausTheme()
            }
            .task(id: TrainingAchievementProgress(snapshot: snapshot)) {
                var ledger = (try? JSONDecoder().decode(TrainingAchievementLedger.self, from: achievementData))
                    ?? TrainingAchievementLedger()
                let new = ledger.observe(TrainingAchievementProgress(snapshot: snapshot))
                if let data = try? JSONEncoder().encode(ledger) { achievementData = data }
                moments.append(contentsOf: new)
            }
    }

    private func tile(_ page: TrainingDestination, value: Int, total: Int? = nil) -> some View {
        Button { destination = page } label: {
            VStack(spacing: Theme.grid * 2) {
                Text(page.title(zh: zh)).font(Theme.label).foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: Theme.grid) {
                    Text("\(value)").font(Theme.title).fontWeight(.medium)
                    if let total {
                        Text("/ \(total)").font(Theme.label).foregroundStyle(Theme.secondary)
                    }
                }.monospacedDigit()
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("training-\(page.id)")
    }
}

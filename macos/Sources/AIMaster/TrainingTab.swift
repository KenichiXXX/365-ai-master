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
        VStack(alignment: .leading, spacing: Theme.grid * 2) {
            if let moment = moments.first {
                Button { moments.removeFirst() } label: {
                    Text("▲ " + moment.title(zh: zh)).font(Theme.title).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.grid * 2)
                        .foregroundStyle(Theme.ink).background(Theme.accentSurface)
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
                        Text("TODAY").font(Theme.label).tracking(2)
                        Text(zh ? "今日修炼" : "Today's training").font(Theme.title)
                        Text(zh ? "暂无修炼记录" : "No training records yet").font(Theme.body)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(Theme.grid * 2)
                        .foregroundStyle(Theme.ink).background(Theme.surface)
                }.buttonStyle(.plain)
            }
            HStack(spacing: Theme.grid) {
                tile(.village, value: "\(snapshot.village?.quests.filter { $0.status == "passed" }.count ?? 0)/9")
                tile(.book, value: "\(snapshot.book?.lit ?? 0)/\(snapshot.book?.total ?? 0)")
                tile(.badges, value: "\((snapshot.badges ?? []).filter(\.earned).count + (snapshot.trainingGame?.weeklyBadges.count ?? 0))")
            }
            if let challenge = snapshot.trainingGame?.weekly {
                Button { destination = .challenge } label: {
                    HStack(spacing: Theme.grid) {
                        Text(TrainingDestination.challenge.title(zh: zh) + " ·").font(Theme.label)
                        Text(challenge.title).font(Theme.body).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(challenge.have)/\(challenge.need)").font(Theme.title).monospacedDigit()
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(Theme.grid * 2).bauhausPanel()
                }.buttonStyle(.plain).accessibilityIdentifier("training-challenge")
            }
        }.bauhausTheme()
            .sheet(item: $destination) { page in
                VStack(alignment: .leading, spacing: Theme.grid) {
                    HStack {
                        Text(page.title(zh: zh)).font(Theme.title)
                        Spacer()
                        Button(zh ? "完成" : "Done") { destination = nil }
                    }.padding(Theme.grid * 2)
                    ThemeRule()
                    ScrollView {
                        TrainingDetailPage(destination: page, snapshot: store.snapshot ?? snapshot, store: store)
                            .padding(Theme.grid * 2).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(width: 440, height: 560).bauhausTheme()
            }
            .task(id: TrainingAchievementProgress(snapshot: snapshot)) {
                var ledger = (try? JSONDecoder().decode(TrainingAchievementLedger.self, from: achievementData))
                    ?? TrainingAchievementLedger()
                let new = ledger.observe(TrainingAchievementProgress(snapshot: snapshot))
                if let data = try? JSONEncoder().encode(ledger) { achievementData = data }
                moments.append(contentsOf: new)
            }
    }

    private func tile(_ page: TrainingDestination, value: String) -> some View {
        Button { destination = page } label: {
            VStack(alignment: .leading, spacing: Theme.grid) {
                Text(page.title(zh: zh)).font(Theme.label)
                Text(value).font(Theme.title).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading).padding(Theme.grid * 2).bauhausPanel()
        }.buttonStyle(.plain).accessibilityIdentifier("training-\(page.id)")
    }
}

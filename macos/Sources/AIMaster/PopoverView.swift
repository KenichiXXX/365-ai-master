import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: SnapshotStore
    @AppStorage("selectedTab") private var selectedTab = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("365 AI Master").font(.headline)
                Spacer()
                Button((store.snapshot?.locale ?? store.locale) == "zh" ? "↻ 重新体检" : "↻ Re-check") { store.recheck() }
                    .disabled(store.isRefreshing)
            }
            Picker(selection: $selectedTab) {
                Text("Check-up", bundle: .module).tag(0)
                Text("Discover", bundle: .module).tag(1)
                Text("Training", bundle: .module).tag(2)
            } label: { Text("Check-up", bundle: .module) }
                .pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !store.onboarded {
                        FirstPracticeView(store: store)
                    } else if let snapshot = store.snapshot {
                        if snapshot.notices?.contains("no_tools") == true {
                            Text(snapshot.labels?.noTools ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                            Button(action: { store.refresh() }) { Text("Check now", bundle: .module) }
                        }
                        switch selectedTab {
                        case 1: TodaySkillTab(snapshot: snapshot, store: store)
                        case 2: TrainingTab(snapshot: snapshot, store: store)
                        default: CheckupTab(snapshot: snapshot, store: store)
                        }
                    } else {
                        Text(store.lastError ?? NSLocalizedString("Loading", bundle: .module, comment: ""))
                        FirstPracticeView(store: store)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.id(selectedTab)
            if store.onboarded && store.isRefreshing {
                ProgressView { Text("Scanning allowed sources", bundle: .module) }
                Button(action: store.cancelRefresh) { Text("Cancel scan", bundle: .module) }
            }
            Divider()
            HStack {
                VStack(alignment: .leading) {
                    if let date = store.lastRun {
                        HStack(spacing: 3) {
                            Text("Updated", bundle: .module)
                            Text(date, style: .time)
                        }
                    }
                    if store.lastError != nil { Text("stale", bundle: .module).foregroundStyle(.orange) }
                }.font(.system(size: 11))
                Spacer()
                Button(action: { store.showSettings = true }) { Text("Settings", bundle: .module) }
            }
        }
        .onAppear { store.resumeEntitlement() }
        .padding(16)
        .frame(width: 440, height: 720)
        .sheet(isPresented: $store.showWeeklyReview) {
            if let snapshot = store.snapshot, store.features.weeklyReview {
                WeeklyReviewSheet(snapshot: snapshot)
            }
        }
        .sheet(isPresented: $store.showProSettings) {
            VStack {
                ScrollView { ProSettingsSection(store: store, zh: store.locale == "zh").padding(20) }
                Button(store.locale == "zh" ? "完成" : "Done") { store.showProSettings = false }.padding()
            }.frame(width: 380, height: 660)
        }
        .sheet(item: $store.reminderCard) { card in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(card.title).font(.title2)
                    Text(card.why)
                    PracticeControls(card: card, store: store, locale: store.snapshot?.locale ?? store.locale)
                    Button(store.locale == "zh" ? "完成" : "Done") { store.reminderCard = nil }
                }.padding(20)
            }.frame(width: 440, height: 480)
        }
        .sheet(isPresented: $store.showSettings) { SettingsView(store: store) }
    }
}

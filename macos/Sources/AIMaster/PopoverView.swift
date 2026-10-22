import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: SnapshotStore
    @AppStorage("selectedTab") private var selectedTab = 0
    @State private var recordedRead: String?

    var body: some View {
        Group {
            VStack(spacing: Theme.sectionGap) {
                HStack {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.accent).frame(width: 9, height: 9)
                        Text("365 AI Master").font(Theme.sectionTitle)
                    }
                    Spacer()
                    Button("↻") { store.recheck() }
                        .accessibilityLabel((store.snapshot?.locale ?? store.locale) == "zh" ? "重新扫描" : "Refresh")
                        .buttonStyle(.plain)
                        .font(Theme.title).foregroundStyle(Theme.secondary)
                        .disabled(store.isRefreshing)
                    Button(Theme.proTitle(isPro: store.isPro)) { store.showProSettings = true }
                        .font(Theme.label)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("header-pro")
                }
                MasterTabBar(selection: $selectedTab, locale: store.snapshot?.locale ?? store.locale)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !store.onboarded {
                            FirstPracticeView(store: store)
                        } else if let snapshot = store.snapshot {
                            if snapshot.notices?.contains("no_tools") == true {
                                Text(snapshot.labels?.noTools ?? "").font(Theme.label).foregroundStyle(Theme.secondary)
                                Button(action: { store.recheck() }) { Text("Check now", bundle: .module) }
                            }
                            switch selectedTab {
                            case 1:
                                TodaySkillTab(snapshot: snapshot, store: store)
                                    .task(id: "\(snapshot.book?.today?.id ?? "")-\(store.isRefreshing)") {
                                        guard !store.isRefreshing, let id = snapshot.book?.today?.id else { return }
                                        let key = id + String(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
                                        guard recordedRead != key else { return }
                                        recordedRead = key
                                        await store.markCardRead(id)?.value
                                        if store.lastError != nil { recordedRead = nil }
                                    }
                            case 2: TrainingTab(snapshot: snapshot, store: store)
                            default: CheckupTab(snapshot: snapshot, store: store, showUsageFooter: false)
                            }
                        } else {
                            Text(store.lastError ?? NSLocalizedString("Loading", bundle: .module, comment: ""))
                            FirstPracticeView(store: store)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.id(selectedTab)
                if selectedTab == 0, store.onboarded, let usage = store.snapshot?.usageSummary {
                    UsageFooter(usage: usage, locale: store.snapshot?.locale ?? store.locale)
                }
                ThemeRule()
                HStack {
                    VStack(alignment: .leading) {
                        if let date = store.lastRun {
                            HStack(spacing: Theme.grid) {
                                Text("Updated", bundle: .module)
                                Text(date, style: .time)
                            }
                        }
                        if store.lastError != nil { Text("stale", bundle: .module).foregroundStyle(Theme.ink) }
                    }.font(Theme.label)
                    Spacer()
                    Button(action: { store.showSettings = true }) { Text("Settings", bundle: .module) }
                }
            }
            .onAppear { store.resumeEntitlement() }
            .padding(Theme.pagePadding)
            .frame(width: 440, height: 720)
            .background(MasterWindowBackground())
            .clipShape(RoundedRectangle(cornerRadius: Theme.outerRadius))
            .sheet(isPresented: $store.showWeeklyReview) {
                if let snapshot = store.snapshot, store.features.weeklyReview {
                    WeeklyReviewSheet(snapshot: snapshot)
                }
            }
            .sheet(isPresented: $store.showProSettings) {
                ProSheet(store: store, zh: store.locale == "zh") { store.showProSettings = false }
            }
            .sheet(item: $store.reminderCard) { card in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.grid) {
                        Text(card.title).font(Theme.title)
                        Text(card.why)
                        PracticeControls(card: card, store: store, locale: store.snapshot?.locale ?? store.locale)
                        Button(store.locale == "zh" ? "完成" : "Done") { store.reminderCard = nil }
                    }.padding(Theme.grid * 2)
                }.frame(width: 440, height: 480).bauhausTheme()
            }
            .sheet(isPresented: $store.showSettings) { SettingsView(store: store) }
        }.bauhausTheme()
    }
}

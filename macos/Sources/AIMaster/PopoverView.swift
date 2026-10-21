import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: SnapshotStore
    @State private var settings = false
    @AppStorage("selectedTab") private var selectedTab = 0

    var body: some View {
        VStack(spacing: 12) {
            Picker(selection: $selectedTab) {
                Text("Check-up", bundle: .module).tag(0)
                Text("New today", bundle: .module).tag(1)
                Text("Training", bundle: .module).tag(2)
            } label: { Text("Check-up", bundle: .module) }
                .pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let snapshot = store.snapshot {
                        if snapshot.notices?.contains("no_tools") == true {
                            Text(snapshot.labels?.noTools ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                            Button(action: { store.refresh() }) { Text("Check now", bundle: .module) }
                        }
                        switch selectedTab {
                        case 1: TodaySkillTab(snapshot: snapshot, store: store)
                        case 2: TrainingTab(snapshot: snapshot)
                        default: CheckupTab(snapshot: snapshot, store: store)
                        }
                    } else {
                        Text(store.lastError ?? NSLocalizedString("Loading", bundle: .module, comment: ""))
                        Button(action: { store.refresh() }) { Text("Check now", bundle: .module) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.id(selectedTab)
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
                Button(action: { settings = true }) { Text("Settings", bundle: .module) }
            }
        }
        .padding(16)
        .frame(width: 440, height: 720)
        .sheet(isPresented: $settings) { SettingsView(store: store) }
    }
}

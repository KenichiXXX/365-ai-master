import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: SnapshotStore
    @State private var settings = false

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let snapshot = store.snapshot {
                        if snapshot.notices?.contains("no_tools") == true {
                            Text(snapshot.labels?.noTools ?? "")
                                .padding(.vertical, 30)
                            Button(action: { store.refresh() }) { Text("Check now", bundle: .module) }
                        } else {
                            if let tip = snapshot.todayTip { TipCard(tip: tip, store: store) }
                            if let village = snapshot.village { VillageGrid(village: village) }
                            DimensionRings(dimensions: snapshot.dimensions ?? [])
                            UsageSection(snapshot: snapshot)
                        }
                    } else {
                        Text(store.lastError ?? NSLocalizedString("Loading", bundle: .module, comment: ""))
                        Button(action: { store.refresh() }) { Text("Check now", bundle: .module) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
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
                }.font(.caption2)
                Spacer()
                Button(action: { settings = true }) { Text("Settings", bundle: .module) }
                Button(action: { NSApp.terminate(nil) }) { Text("Quit", bundle: .module) }
            }
        }
        .padding(16)
        .frame(width: 360, height: 560)
        .sheet(isPresented: $settings) { SettingsView(store: store) }
    }
}

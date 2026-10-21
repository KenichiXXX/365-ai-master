import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var store: SnapshotStore
    @Environment(\.dismiss) private var dismiss
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError = false
    @State private var showSnapshot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings", bundle: .module).font(.title2)
            ForEach(SnapshotStore.allTools, id: \.self) { tool in
                Toggle(SnapshotStore.toolNames[tool] ?? tool, isOn: Binding(
                    get: { store.enabledTools.contains(tool) },
                    set: { enabled in
                        store.enabledTools = SnapshotStore.allTools.filter {
                            $0 == tool ? enabled : store.enabledTools.contains($0)
                        }
                    }
                ))
            }
            Picker(selection: $store.refreshSeconds) {
                ForEach([30, 60, 300], id: \.self) { seconds in Text("\(seconds) s").tag(seconds) }
            } label: { Text("Refresh interval", bundle: .module) }
            Toggle(isOn: Binding(get: { launchAtLogin }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                    loginError = enabled && !launchAtLogin
                } catch { loginError = true }
            })) { Text("Launch at login", bundle: .module) }
            if loginError { Text("Login item unavailable", bundle: .module).font(.caption).foregroundStyle(.orange) }
            Button(action: { showSnapshot = true }) { Text("View my snapshot", bundle: .module) }
                .disabled(store.snapshot == nil)
            Text("This app makes no network connections.", bundle: .module).font(.caption)
            Button(action: { dismiss() }) { Text("Done", bundle: .module) }
        }
        .padding(20).frame(width: 340)
        .sheet(isPresented: $showSnapshot) {
            VStack {
                ScrollView([.horizontal, .vertical]) {
                    Text(store.snapshotJSON).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: { showSnapshot = false }) { Text("Done", bundle: .module) }
            }.padding().frame(width: 600, height: 450)
        }
    }
}

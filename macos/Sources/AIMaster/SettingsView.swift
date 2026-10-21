import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var store: SnapshotStore
    @Environment(\.dismiss) private var dismiss
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError = false
    @State private var showSnapshot = false

    var body: some View {
        ScrollView {
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
                    ForEach(SnapshotStore.refreshIntervals, id: \.self) { seconds in Text("\(seconds) s").tag(seconds) }
                } label: { Text("Refresh interval", bundle: .module) }
                Toggle(isOn: Binding(get: { launchAtLogin }, set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                        loginError = enabled && !launchAtLogin
                    } catch { loginError = true }
                })) { Text("Launch at login", bundle: .module) }
                if loginError { Text("Login item unavailable", bundle: .module).font(.system(size: 11)).foregroundStyle(.orange) }
                Button(action: { showSnapshot = true }) { Text("View my snapshot", bundle: .module) }
                    .disabled(store.snapshot == nil)
                OptionalPracticePreferences(store: store)
                Text(store.locale == "zh" ? "关闭后停止上报，服务器上已有的排名记录仍会保留。"
                     : "Turning sharing off stops reporting. Your existing ranking record stays on the server.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button(action: { store.resetActionPreferences() }) {
                    Text("Reset suggestion preferences", bundle: .module)
                }.disabled(store.isRefreshing)
                ProSettingsSection(store: store, zh: store.locale == "zh")
                Button(action: { NSApp.terminate(nil) }) { Text("Quit", bundle: .module) }
                Button(action: { dismiss() }) { Text("Done", bundle: .module) }
            }
            .padding(20)
        }.frame(width: 380, height: 660)
        .sheet(isPresented: $showSnapshot) {
            VStack {
                ScrollView([.horizontal, .vertical]) {
                    Text(store.snapshotJSON).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: { showSnapshot = false }) { Text("Done", bundle: .module) }
            }.padding().frame(width: 600, height: 450)
        }
    }
}

struct ProSettingsSection: View {
    @ObservedObject var store: SnapshotStore
    let zh: Bool
    @State private var activationKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("365 AI Master Pro").font(.headline)
            if store.isPro, let license = store.license {
                Text(verbatim: zh ? "Pro 已激活，到期 \(license.exp)" : "Pro activated, expires \(license.exp)")
            } else {
                Text(zh ? "创始价 $12/年" : "Founding price $12/year")
                Text(zh ? "成长曲线：30 天分数走势、本周比上周" : "Growth curve: 30-day scores and week-over-week change")
                Text(zh ? "每周复盘：周一推送一页周报" : "Weekly review: a one-page report on Monday")
                Text(zh ? "技能图鉴随时选学、完整榜单 Top 20" : "Learn any skill anytime, full Top 20 ranking")
                Text(zh ? "四维分别排名" : "Rankings for each of the four dimensions")
                if License.checkoutURL != "REPLACE_WAFFO_CHECKOUT", let url = URL(string: License.checkoutURL) {
                    Button(zh ? "去付款" : "Buy") { NSWorkspace.shared.open(url) }
                } else {
                    Text(zh ? "付款通道开通中，可联系作者获取创始激活码" : "Checkout opening soon")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            TextField(zh ? "输入激活码" : "Enter activation key", text: $activationKey)
                .textFieldStyle(.roundedBorder)
            Button(zh ? "激活" : "Activate") {
                if store.activateLicense(activationKey) { activationKey = "" }
            }
            if let error = store.licenseError {
                Text(error.message(locale: zh ? "zh" : "en")).foregroundStyle(.red)
            }
        }.font(.system(size: 12))
    }
}

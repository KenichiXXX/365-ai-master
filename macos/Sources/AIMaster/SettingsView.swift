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
                ProTrialSection(store: store, zh: zh)
                Divider()
                Text(zh ? "创始价 $12/年" : "Founding price $12/year")
                Text(zh ? "成长曲线：30 天分数走势、本周比上周" : "Growth curve: 30-day scores and week-over-week change")
                Text(zh ? "每周复盘：本地生成一页周报，可选开启提醒" : "Weekly review: a local report with optional reminders")
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

struct ReminderSettings: View {
    @ObservedObject var store: SnapshotStore
    private var zh: Bool { store.locale == "zh" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(zh ? "提醒默认关闭" : "Reminders are off by default").font(.caption)
            Toggle(zh ? "每日练习提醒" : "Daily practice reminder", isOn: $store.dailyPracticeReminders)
            Toggle(zh ? "周复盘提醒" : "Weekly review reminder", isOn: $store.notificationsEnabled)
                .disabled(!store.features.weeklyReview)
            if !store.features.weeklyReview {
                Text(zh ? "周复盘提醒需 Pro 权益" : "Weekly review reminders require Pro").font(.caption)
            }
            Toggle(zh ? "暂停提醒" : "Pause reminders", isOn: $store.remindersPaused)
            Picker(zh ? "提醒时间" : "Reminder time", selection: $store.reminderHour) {
                ForEach(9..<21, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour)).tag(hour)
                }
            }
            Text(zh ? "21:00–09:00 静默，错过不补发；系统专注模式照常生效。"
                 : "Quiet hours 21:00–09:00. Missed reminders are skipped. Focus is respected.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ProTrialSection: View {
    @ObservedObject var store: SnapshotStore
    let zh: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch store.trialStatus {
            case .eligible:
                Text(zh ? "免费体验 Pro 14 天" : "Try Pro free for 14 days").font(.headline)
                Text(zh ? "无需银行卡，不自动扣款。体验到期后回到免费版，历史记录保留。"
                     : "No card required and no automatic charge. After the trial, return to Free and keep your history.")
                Button(zh ? "开始体验" : "Start trial") { store.startProTrial() }
            case .active(let end):
                Text(verbatim: (zh ? "体验至 " : "Trial until ") + formatted(end))
                Text(zh ? "无需银行卡，不自动扣款。体验到期后回到免费版，历史记录保留。"
                     : "No card required and no automatic charge. After the trial, return to Free and keep your history.")
            case .expired(let reason):
                if reason == .clockRollback {
                    Text(zh ? "设备时间发生回拨，体验已结束" : "The device clock moved backwards. The trial has ended.")
                }
                Text(zh ? "体验已结束，历史记录已保留" : "Trial ended. Your history is preserved.")
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

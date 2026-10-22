import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var store: SnapshotStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError = false
    @State private var showSnapshot = false
    @State private var showLocalValidation = false
    @State private var showConsent = false
    @State private var showPro = false
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(zh ? "设置" : "Settings").font(.title2)
                Spacer()
                Button(zh ? "完成" : "Done") { dismiss() }
            }
            group(zh ? "通用" : "General") {
                Toggle(zh ? "开机启动" : "Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if loginError {
                    Text("Login item unavailable", bundle: .module).font(.caption).foregroundStyle(.orange)
                }
                Picker(zh ? "刷新频率" : "Refresh interval", selection: $store.refreshSeconds) {
                    ForEach(SnapshotStore.refreshIntervals, id: \.self) { seconds in
                        Text("\(seconds) s").tag(seconds)
                    }
                }
            }
            group(zh ? "隐私" : "Privacy") {
                Toggle(zh ? "匿名排名" : "Anonymous ranking", isOn: Binding(
                    get: { store.shareAnonymousScore },
                    set: { if $0 { showConsent = true } else { store.shareAnonymousScore = false } }
                ))
                Toggle(zh ? "每日榜单更新" : "Daily ranking updates", isOn: Binding(
                    get: { store.publicDownloads == true }, set: { store.publicDownloads = $0 }
                ))
                Button(zh ? "查看我的数据" : "View my data") { showSnapshot = true }
                    .disabled(store.snapshot == nil)
            }
            group("Pro") {
                HStack {
                    Text(store.isPro ? (zh ? "Pro 已开启" : "Pro is active") : (zh ? "免费版" : "Free"))
                    Spacer()
                    Button(zh ? "输入激活码" : "Enter activation key") { showPro = true }
                    Button(store.license != nil ? (zh ? "管理" : "Manage") : (zh ? "购买" : "Buy")) { showPro = true }
                }
            }
            group(zh ? "关于" : "About") {
                HStack {
                    Text((zh ? "版本 " : "Version ") +
                         (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"))
                    Spacer()
                    Button(zh ? "反馈" : "Feedback") { showLocalValidation = true }.disabled(store.snapshot == nil)
                    Button(zh ? "退出" : "Quit") { NSApp.terminate(nil) }
                }
            }
            DisclosureGroup(zh ? "高级" : "Advanced") {
                ScrollView {
                    advanced.padding(.top, 8)
                }.frame(height: 130)
            }
        }
        .font(.system(size: 12))
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showConsent) {
            VStack(alignment: .leading, spacing: 12) {
                ScoreConsentPanel(store: store, zh: zh, close: { showConsent = false })
                Text(zh ? "关闭后停止上报，已有的排名记录仍会保留。"
                     : "Turning sharing off stops reporting. Existing ranking records are kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(width: 400)
        }
        .sheet(isPresented: $showPro) {
            VStack {
                ScrollView { ProSettingsSection(store: store, zh: zh).padding(20) }
                Button(zh ? "完成" : "Done") { showPro = false }.padding()
            }.frame(width: 440, height: 580)
        }
        .sheet(isPresented: $showLocalValidation) {
            if let snapshot = store.snapshot { LocalValidationView(snapshot: snapshot, store: store) }
        }
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

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            Button(shareCopy("Local validation", store.locale)) {
                store.refresh()
                showLocalValidation = true
            }.disabled(store.snapshot == nil)
            ReminderSettings(store: store)
            Text("Public download explanation", bundle: .module).font(.caption)
            Text(zh ? "关闭匿名排名后停止上报，已有的排名记录仍会保留。"
                 : "Turning sharing off stops reporting. Existing ranking records are kept.")
                .font(.caption).foregroundStyle(.secondary)
            Button(action: { store.resetActionPreferences() }) {
                Text("Reset suggestion preferences", bundle: .module)
            }.disabled(store.isRefreshing)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = enabled && !launchAtLogin
        } catch { loginError = true }
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
            if let license = store.signedLicense {
                Text(verbatim: t("Local activation key valid through {date}").replacingOccurrences(of: "{date}", with: DisplayDate.short(license.exp, locale: zh ? "zh" : "en", year: true)))
                if case .active(_, let end) = store.renewalState {
                    Text(verbatim: t("Verified paid period ends {date}").replacingOccurrences(of: "{date}", with: DisplayDate.short(end, locale: zh ? "zh" : "en", year: true)))
                }
                Button(t("Refresh activation key")) { store.refreshLicense(explicit: true) }
                    .disabled(store.licenseRefreshTask != nil)
            }
            if store.signedLicense != nil || store.renewalState == .pending {
                Text(t(store.renewalState.messageKey)).foregroundStyle(.secondary)
            }
            if !store.isPro {
                ProTrialSection(store: store, zh: zh)
                Text(zh ? "成长曲线：30 天分数走势、本周比上周" : "Growth curve: 30-day scores and week-over-week change")
                Text(zh ? "每周复盘：本地生成一页周报，可选开启提醒" : "Weekly review: a local report with optional reminders")
                Text(zh ? "技能图鉴随时选学、完整榜单 Top 20" : "Learn any skill anytime, full Top 20 ranking")
                Text(zh ? "四维分别排名" : "Rankings for each of the four dimensions")
            }
            PurchaseTermsView(zh: zh)
            Text(t("Payment integration is not verified. Checkout is unavailable")).foregroundStyle(.secondary)
            CourseSourceSection(store: store, zh: zh)
            Button(t("Buy")) {
                if store.purchaseConfiguration.openCheckout(termsPresented: true, source: store.checkoutSource,
                    open: { NSWorkspace.shared.open($0) }) { store.checkoutReturned() }
            }.disabled(store.purchaseConfiguration.checkout(source: store.checkoutSource) == nil)
            Button(t("Manage or cancel subscription")) {
                if let url = store.purchaseConfiguration.managementURL { NSWorkspace.shared.open(url) }
            }.disabled(store.purchaseConfiguration.managementURL == nil)
            Toggle(t("Refresh license automatically"), isOn: $store.autoRefreshLicense)
            Text(t("Automatic key refresh sends your license ID and signed activation key to the license service, never usage records"))
                .font(.caption).foregroundStyle(.secondary)
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

    private func t(_ key: String) -> String { PurchaseTerms.localized(key, locale: zh ? "zh" : "en") }
}

struct PurchaseTermsView: View {
    let zh: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(PurchaseTerms.lines(locale: zh ? "zh" : "en"), id: \.self) { line in
                Text(verbatim: line).fixedSize(horizontal: false, vertical: true)
            }
        }.font(.caption)
    }
}

struct CourseSourceSection: View {
    @ObservedObject var store: SnapshotStore
    let zh: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(PurchaseTerms.localized("Course source code (optional)", locale: zh ? "zh" : "en"),
                text: Binding(get: { store.courseSourceCode }, set: { store.courseSourceCode = String($0.prefix(32)) }))
                .textFieldStyle(.roundedBorder)
            if let source = store.courseSource, let card = store.courseCard {
                Text(verbatim: source.title[zh ? "zh" : "en"] ?? source.code)
                DisclosureGroup(card.title) {
                    SkillCardDetails(card: card, todayID: store.snapshot?.book?.today?.id,
                                     store: store, locale: zh ? "zh" : "en")
                }
                Toggle(PurchaseTerms.localized("Include this source code at checkout", locale: zh ? "zh" : "en"),
                       isOn: $store.includeCourseSource)
            }
        }
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

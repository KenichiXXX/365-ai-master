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

    static func versionLabel(bundle: Bundle = .main, locale: String) -> String {
        guard bundle.bundleURL.pathExtension == "app",
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else { return locale == "zh" ? "开发版" : "Dev build" }
        return (locale == "zh" ? "版本 " : "Version ") + version
    }

    static func intervalLabel(_ seconds: Int, locale: String) -> String {
        "\(seconds / 60)" + (locale == "zh" ? " 分钟" : " min")
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                HStack {
                    Text(zh ? "设置" : "Settings").font(Theme.title)
                    Spacer()
                    Button(zh ? "完成" : "Done") { dismiss() }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.sectionGap) {
                        group(zh ? "通用" : "General") {
                            Toggle(zh ? "开机启动" : "Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                            if loginError {
                                Text("Login item unavailable", bundle: .module).font(Theme.label).foregroundStyle(Theme.ink)
                            }
                            ThemeRule()
                            ThemeMenu(title: zh ? "刷新频率" : "Refresh interval", selection: $store.refreshSeconds,
                                      options: SnapshotStore.refreshIntervals,
                                      label: { Self.intervalLabel($0, locale: zh ? "zh" : "en") })
                        }
                        group(zh ? "隐私" : "Privacy") {
                            Toggle(zh ? "匿名排名" : "Anonymous ranking", isOn: Binding(
                                get: { store.shareAnonymousScore },
                                set: { if $0 { showConsent = true } else { store.shareAnonymousScore = false } }
                            ))
                            ThemeRule()
                            Toggle(zh ? "每日榜单更新" : "Daily ranking updates", isOn: Binding(
                                get: { store.publicDownloads == true }, set: { store.publicDownloads = $0 }
                            ))
                            ThemeRule()
                            Button(zh ? "查看我的数据" : "View my data") { showSnapshot = true }
                                .disabled(store.snapshot == nil)
                        }
                        group("Pro") {
                            HStack {
                                Text(store.isPro ? (zh ? "Pro 已开启" : "Pro is active") : (zh ? "免费版" : "Free"))
                                Spacer()
                                Button(zh ? "输入激活码" : "Enter activation key") { showPro = true }
                                Button(store.license != nil ? (zh ? "管理" : "Manage") : (zh ? "查看 Pro" : "Explore Pro")) { showPro = true }
                            }
                        }
                        group(zh ? "关于" : "About") {
                            HStack {
                                Text(Self.versionLabel(locale: zh ? "zh" : "en"))
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
                }
            }
            .font(Theme.body)
            .padding(Theme.pagePadding)
            .frame(width: 440, height: 600)
            .sheet(isPresented: $showConsent) {
                VStack(alignment: .leading, spacing: Theme.grid) {
                    ScoreConsentPanel(store: store, zh: zh, close: { showConsent = false })
                    Text(zh ? "关闭后停止上报，已有的排名记录仍会保留。"
                         : "Turning sharing off stops reporting. Existing ranking records are kept.")
                        .font(Theme.label).foregroundStyle(Theme.secondary)
                }.padding(Theme.pagePadding).frame(width: 400)
                    .background(MasterWindowBackground()).bauhausTheme()
            }
            .sheet(isPresented: $showPro) {
                ProSheet(store: store, zh: zh) { showPro = false }
            }
            .sheet(isPresented: $showLocalValidation) {
                if let snapshot = store.snapshot { LocalValidationView(snapshot: snapshot, store: store) }
            }
            .sheet(isPresented: $showSnapshot) {
                VStack {
                    ScrollView([.horizontal, .vertical]) {
                        Text(store.snapshotJSON).font(Theme.label.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(action: { showSnapshot = false }) { Text("Done", bundle: .module) }
                }.padding().frame(width: 600, height: 450).bauhausTheme()
            }
        }.background(MasterWindowBackground()).bauhausTheme()
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.grid * 3) {
            Text(title).font(Theme.sectionTitle)
            content()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bauhausPanel()
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: Theme.grid) {
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
            Text("Public download explanation", bundle: .module).font(Theme.label)
            Text(zh ? "关闭匿名排名后停止上报，已有的排名记录仍会保留。"
                 : "Turning sharing off stops reporting. Existing ranking records are kept.")
                .font(Theme.label).foregroundStyle(Theme.secondary)
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
    @State private var showActivation = false

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                Text("365 AI MASTER PRO").font(Theme.title)
                Text(zh ? "$12 / 年 · 创始价" : "$12 / year · Founding price")
                    .font(Theme.title).foregroundStyle(Theme.ink)
                    .padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                VStack(alignment: .leading, spacing: Theme.grid) {
                    benefit(zh ? "成长曲线" : "Growth curve")
                    benefit(zh ? "每周复盘" : "Weekly review")
                    benefit(zh ? "Top 20 完整榜单" : "Full Top 20 rankings")
                    benefit(zh ? "四维全球排名" : "Global rankings in four dimensions")
                }
                if !store.isPro { ProTrialSection(store: store, zh: zh) }
                Button(zh ? "输入激活码" : "Enter activation key") { showActivation.toggle() }
                    .buttonStyle(ThemeButtonStyle())
                    .accessibilityIdentifier("pro-enter-key")
                if showActivation {
                    TextField(zh ? "输入激活码" : "Enter activation key", text: $activationKey)
                        .textFieldStyle(.plain).padding(Theme.grid).bauhausPanel()
                    Button(zh ? "激活" : "Activate") {
                        if store.activateLicense(activationKey) { activationKey = "" }
                    }
                    if let error = store.licenseError {
                        Text("⚠︎ " + error.message(locale: zh ? "zh" : "en")).foregroundStyle(Theme.secondary)
                    }
                }
                ThemeRule()
                if let license = store.signedLicense {
                    Text(verbatim: t("Local activation key valid through {date}").replacingOccurrences(of: "{date}", with: DisplayDate.short(license.exp, locale: zh ? "zh" : "en", year: true)))
                    if case .active(_, let end) = store.renewalState {
                        Text(verbatim: t("Verified paid period ends {date}").replacingOccurrences(of: "{date}", with: DisplayDate.short(end, locale: zh ? "zh" : "en", year: true)))
                    }
                    Button(t("Refresh activation key")) { store.refreshLicense(explicit: true) }
                        .disabled(store.licenseRefreshTask != nil)
                }
                if store.signedLicense != nil || store.renewalState == .pending {
                    Text(t(store.renewalState.messageKey)).foregroundStyle(Theme.secondary)
                }
                if store.purchaseConfiguration.checkout(source: store.checkoutSource) != nil {
                    PurchaseTermsView(zh: zh)
                    Button(t("Buy")) {
                        if store.purchaseConfiguration.openCheckout(termsPresented: true, source: store.checkoutSource,
                            open: { NSWorkspace.shared.open($0) }) { store.checkoutReturned() }
                    }.accessibilityIdentifier("pro-checkout")
                } else {
                    Text(zh ? "付款通道开通中" : "Payments coming soon")
                        .font(Theme.label).foregroundStyle(Theme.secondary)
                }
                if let url = store.purchaseConfiguration.managementURL {
                    Button(t("Manage or cancel subscription")) { NSWorkspace.shared.open(url) }
                }
                DisclosureGroup(zh ? "订阅条款与设置" : "Subscription terms and settings") {
                    PurchaseTermsView(zh: zh)
                    CourseSourceSection(store: store, zh: zh)
                    Toggle(t("Refresh license automatically"), isOn: $store.autoRefreshLicense)
                    Text(t("Automatic key refresh sends your license ID and signed activation key to the license service, never usage records"))
                        .font(Theme.label).foregroundStyle(Theme.secondary)
                }
            }.font(Theme.body)
        }.bauhausTheme()
    }

    private func benefit(_ title: String) -> some View {
        HStack(spacing: Theme.grid) {
            Text("▲").font(Theme.label)
            Text(title).font(Theme.body)
        }
    }

    private func t(_ key: String) -> String { PurchaseTerms.localized(key, locale: zh ? "zh" : "en") }
}

struct PurchaseTermsView: View {
    let zh: Bool
    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.grid) {
                ForEach(PurchaseTerms.lines(locale: zh ? "zh" : "en"), id: \.self) { line in
                    Text(verbatim: line).fixedSize(horizontal: false, vertical: true)
                }
            }.font(Theme.body)
        }.bauhausTheme()
    }
}

struct CourseSourceSection: View {
    @ObservedObject var store: SnapshotStore
    let zh: Bool
    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.grid) {
                TextField(PurchaseTerms.localized("Course source code (optional)", locale: zh ? "zh" : "en"),
                    text: Binding(get: { store.courseSourceCode }, set: { store.courseSourceCode = String($0.prefix(32)) }))
                    .textFieldStyle(.plain).padding(Theme.grid).bauhausPanel()
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
        }.bauhausTheme()
    }
}

struct ReminderSettings: View {
    @ObservedObject var store: SnapshotStore
    private var zh: Bool { store.locale == "zh" }
    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text(zh ? "提醒默认关闭" : "Reminders are off by default").font(Theme.label)
                Toggle(zh ? "每日练习提醒" : "Daily practice reminder", isOn: $store.dailyPracticeReminders)
                Toggle(zh ? "周复盘提醒" : "Weekly review reminder", isOn: $store.notificationsEnabled)
                    .disabled(!store.features.weeklyReview)
                if !store.features.weeklyReview {
                    Text(zh ? "周复盘提醒需 Pro 权益" : "Weekly review reminders require Pro").font(Theme.label)
                }
                Toggle(zh ? "暂停提醒" : "Pause reminders", isOn: $store.remindersPaused)
                ThemeMenu(title: zh ? "提醒时间" : "Reminder time", selection: $store.reminderHour,
                          options: Array(9..<21), label: { String(format: "%02d:00", $0) })
                Text(zh ? "21:00–09:00 静默，错过不补发；系统专注模式照常生效。"
                     : "Quiet hours 21:00–09:00. Missed reminders are skipped. Focus is respected.")
                    .font(Theme.label).foregroundStyle(Theme.secondary)
            }
        }.bauhausTheme()
    }
}

struct ProTrialSection: View {
    @ObservedObject var store: SnapshotStore
    let zh: Bool

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                switch store.trialStatus {
                case .eligible:
                    Text(zh ? "无需银行卡，不自动扣款。体验到期后回到免费版，历史记录保留。"
                         : "No card required and no automatic charge. After the trial, return to Free and keep your history.")
                        .font(Theme.label).foregroundStyle(Theme.secondary)
                    Button { store.startProTrial() } label: {
                        Text(zh ? "开始 14 天免费试用" : "Start 14-day free trial")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(ThemeButtonStyle(primary: true)).accessibilityIdentifier("pro-start-trial")
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
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

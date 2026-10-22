import SwiftUI
import ServiceManagement

struct SettingsPage: View {
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError = false
    @State private var askConsent = false

    static func versionLabel(bundle: Bundle = .main, locale: String) -> String {
        guard bundle.bundleURL.pathExtension == "app",
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else { return tr(locale, "开发版", "Dev build") }
        return tr(locale, "版本 ", "Version ") + version
    }

    var body: some View {
        VStack(spacing: Theme.gap) {
            group(tr(locale, "全球排名", "Global ranking")) {
                toggle(tr(locale, "匿名参与全球排名", "Join the global ranking anonymously"), isOn: Binding(
                    get: { store.shareAnonymousScore },
                    set: { if $0 { askConsent = true } else { store.shareAnonymousScore = false } }))
                if askConsent {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ScoreConsent.explanation(locale: locale)).font(Theme.caption).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button(tr(locale, "同意并加入", "Agree and join")) {
                                askConsent = false
                                Task { await store.allowScoreSharing() }
                            }.buttonStyle(PrimaryButtonStyle(expand: false))
                            Button(tr(locale, "暂不", "Not now")) { askConsent = false }.buttonStyle(SecondaryButtonStyle())
                        }
                    }.padding(10).background(Theme.goldSoft, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                } else if store.shareAnonymousScore {
                    note(store.ranking.map { $0.caption(locale: locale) } ?? store.rankingCaption(locale: locale))
                }
            }
            group(tr(locale, "提醒", "Reminders")) {
                toggle(tr(locale, "每天提醒我练一招", "Remind me to practise daily"), isOn: $store.dailyPracticeReminders)
                if store.dailyPracticeReminders {
                    HStack {
                        Text(tr(locale, "提醒时间", "Time")).font(Theme.body)
                        Spacer()
                        Picker("", selection: $store.reminderHour) {
                            ForEach(9..<21, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                }
                toggle(tr(locale, "周一提醒我看周报", "Weekly review on Mondays"), isOn: $store.notificationsEnabled)
                    .disabled(!store.features.weeklyReview)
                note(tr(locale, "21:00 到 09:00 不打扰；错过不补发。", "Quiet from 21:00 to 09:00. Missed reminders are skipped."))
            }
            group(tr(locale, "数据与隐私", "Data and privacy")) {
                toggle(tr(locale, "每天下载一次最新榜单", "Download fresh rankings daily"),
                       isOn: Binding(get: { store.publicDownloads == true }, set: { store.publicDownloads = $0 }))
                row(tr(locale, "怎么算的", "How it works")) { open(.howItWorks) }
                row(tr(locale, "查看我的数据", "View my data")) { open(.data) }
            }
            group(tr(locale, "读取哪些工具", "Tools to read")) {
                ForEach(SnapshotStore.allTools, id: \.self) { tool in
                    toggle(SnapshotStore.toolNames[tool] ?? tool, isOn: Binding(
                        get: { store.enabledTools.contains(tool) },
                        set: { enabled in
                            store.enabledTools = SnapshotStore.allTools.filter { $0 == tool ? enabled : store.enabledTools.contains($0) }
                        }))
                }
            }
            group(tr(locale, "通用", "General")) {
                toggle(tr(locale, "开机自动启动", "Open at login"), isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if loginError { note(tr(locale, "系统没有允许，稍后在系统设置里打开。", "macOS didn't allow it. Try again in System Settings.")) }
                HStack {
                    Text(tr(locale, "自动刷新", "Refresh every")).font(Theme.body)
                    Spacer()
                    Picker("", selection: $store.refreshSeconds) {
                        ForEach(SnapshotStore.refreshIntervals, id: \.self) { Text(tr(locale, "\($0 / 60) 分钟", "\($0 / 60) min")).tag($0) }
                    }.labelsHidden().fixedSize()
                }
            }
            group("Pro") {
                row(store.isPro ? tr(locale, "Pro 已开启", "Pro is on") : tr(locale, "免费版 · 了解 Pro", "Free · See Pro")) { open(.pro) }
            }
            HStack {
                Text(Self.versionLabel(locale: locale)).font(Theme.caption).foregroundStyle(Theme.tertiary)
                Spacer()
                Button(tr(locale, "反馈", "Feedback")) { open(.feedback) }
                    .buttonStyle(LinkButtonStyle(color: Theme.secondary, font: Theme.caption)).disabled(store.snapshot == nil)
                Button(tr(locale, "重置建议偏好", "Reset suggestions")) { store.resetActionPreferences() }
                    .buttonStyle(LinkButtonStyle(color: Theme.secondary, font: Theme.caption)).disabled(store.isRefreshing)
                Button(tr(locale, "退出", "Quit")) { NSApp.terminate(nil) }
                    .buttonStyle(LinkButtonStyle(color: Theme.secondary, font: Theme.caption))
            }.padding(.horizontal, 4)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            VStack(alignment: .leading, spacing: 10) { content() }.card()
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(Theme.body)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.body)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = enabled && !launchAtLogin
        } catch { loginError = true }
    }
}

struct HowItWorksPage: View {
    let locale: String

    var body: some View {
        VStack(spacing: Theme.gap) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(AnalysisPromise.lines(locale: locale).enumerated()), id: \.offset) { index, line in
                    Label(line, systemImage: ["doc.text.magnifyingglass", "function", "bolt.slash", "icloud.slash"][min(index, 3)])
                        .font(Theme.body)
                }
            }.card()
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: tr(locale, "分数怎么来", "Where the score comes from"))
                Text(tr(locale, "从本机日志里统计四件事：模型用得对不对、时间是否集中、会话是否整洁、有没有把常干的活沉淀成技能。每项满分 100，按权重合成总分。所有阈值都写在规则里，同样的记录永远算出同样的分。",
                        "We count four things in your local logs: model choice, focus rhythm, session tidiness, and how much repeat work you've turned into skills. Each is out of 100 and weighted into the total. Same records, same score, every time."))
                    .font(Theme.body).fixedSize(horizontal: false, vertical: true)
            }.card()
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: tr(locale, "什么时候会联网", "When it goes online"))
                Text(tr(locale, "每天下载一次公开的榜单文件（可关）。你主动加入全球排名后，每天最多上传一次总分和四项分数，不含任何记录。激活码只在你点刷新或开启自动续期时联网校验。",
                        "Once a day it downloads a public rankings file (you can turn this off). If you join the global ranking, it uploads your scores at most once a day, never your records. Activation keys are checked only when you refresh them or turn on auto-refresh."))
                    .font(Theme.body).fixedSize(horizontal: false, vertical: true)
            }.card()
        }
    }
}

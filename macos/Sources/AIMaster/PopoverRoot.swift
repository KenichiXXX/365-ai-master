import SwiftUI

enum Page: Hashable {
    case dimension(String), path, discover, weekly, pro, settings, howItWorks, share, feedback, data
}

struct PopoverRoot: View {
    @ObservedObject var store: SnapshotStore
    @State private var stack: [Page]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: SnapshotStore, stack: [Page] = []) {
        self.store = store
        _stack = State(initialValue: stack)
    }
    private var locale: String { store.snapshot?.locale ?? store.locale }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            if !store.onboarded {
                OnboardingPage(store: store, locale: locale)
                    .transition(.opacity)
            } else if let page = stack.last {
                VStack(spacing: 0) {
                    PageHeader(title: title(page), locale: locale) { pop() }
                    ScrollView {
                        content(page).padding(.horizontal, Theme.page).padding(.bottom, Theme.page)
                    }.scrollIndicators(.never)
                }
                .id(page)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            } else {
                VStack(spacing: 0) {
                    HomeHeader(store: store, locale: locale, open: push)
                    ScrollView {
                        HomePage(store: store, locale: locale, open: push)
                            .padding(.horizontal, Theme.page).padding(.bottom, Theme.gap)
                    }.scrollIndicators(.never)
                    HomeFooter(store: store, locale: locale, open: push)
                }
                .transition(.move(edge: .leading))
            }
        }
        .frame(width: Theme.width, height: Theme.height)
        .appStyle()
        .onAppear { store.resumeEntitlement() }
        .onChange(of: store.showSettings) { if $0 { store.showSettings = false; push(.settings) } }
        .onChange(of: store.showProSettings) { if $0 { store.showProSettings = false; push(.pro) } }
        .onChange(of: store.showWeeklyReview) { if $0 { store.showWeeklyReview = false; push(.weekly) } }
        .onChange(of: store.reminderCard?.id) { if $0 != nil { store.reminderCard = nil; withAnimation(animation) { stack = [] } } }
    }

    private var animation: Animation? { reduceMotion ? nil : Theme.motion }

    private func push(_ page: Page) {
        guard stack.last != page else { return }
        withAnimation(animation) { stack.append(page) }
    }

    private func pop() {
        withAnimation(animation) { _ = stack.popLast() }
    }

    private func title(_ page: Page) -> String {
        switch page {
        case .dimension(let key):
            return store.snapshot?.dimensions?.first { $0.key == key }.map { DimensionCopy.name($0, locale: locale) } ?? ""
        case .path: return tr(locale, "修炼路线", "Your path")
        case .discover: return tr(locale, "今日新榜", "Trending today")
        case .weekly: return tr(locale, "本周复盘", "Weekly review")
        case .pro: return "365 AI Master Pro"
        case .settings: return tr(locale, "设置", "Settings")
        case .howItWorks: return tr(locale, "怎么算的", "How it works")
        case .share: return tr(locale, "分享我的段位", "Share my rank")
        case .feedback: return tr(locale, "反馈", "Feedback")
        case .data: return tr(locale, "我的数据", "My data")
        }
    }

    @ViewBuilder
    private func content(_ page: Page) -> some View {
        switch page {
        case .dimension(let key):
            if let snapshot = store.snapshot, let dimension = snapshot.dimensions?.first(where: { $0.key == key }) {
                DimensionPage(dimension: dimension, snapshot: snapshot, store: store, locale: locale, open: push)
            }
        case .path: PathPage(store: store, locale: locale, open: push)
        case .discover: DiscoverPage(store: store, locale: locale, open: push)
        case .weekly: WeeklyPage(store: store, locale: locale, open: push)
        case .pro: ProPage(store: store, locale: locale)
        case .settings: SettingsPage(store: store, locale: locale, open: push)
        case .howItWorks: HowItWorksPage(locale: locale)
        case .share:
            if let snapshot = store.snapshot { SharePage(snapshot: snapshot, store: store, locale: locale) }
        case .feedback:
            if let snapshot = store.snapshot { LocalValidationView(snapshot: snapshot, store: store) }
        case .data: DataPage(json: store.snapshotJSON)
        }
    }
}

struct PageHeader: View {
    let title: String
    let locale: String
    let back: () -> Void

    var body: some View {
        ZStack {
            Text(title).font(Theme.headline).lineLimit(1)
            HStack {
                Button(action: back) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text(tr(locale, "返回", "Back"))
                    }
                }
                .buttonStyle(LinkButtonStyle(color: Theme.secondary))
                .keyboardShortcut("[", modifiers: .command)
                Spacer()
            }
        }
        .padding(.horizontal, Theme.page).frame(height: 48)
    }
}

struct HomeHeader: View {
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            AppMark()
            Text("365 AI Master").font(Theme.bodyStrong)
            Spacer()
            Button { store.recheck() } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing && !reduceMotion ? 360 : 0))
                    .animation(store.isRefreshing && !reduceMotion
                               ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                               value: store.isRefreshing)
            }
            .buttonStyle(IconButtonStyle())
            .disabled(store.isRefreshing)
            .help(tr(locale, "重新检查", "Check again"))
            .keyboardShortcut("r", modifiers: .command)
            Button { open(.pro) } label: { ProBadge(store: store, locale: locale) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("header-pro")
        }
        .padding(.horizontal, Theme.page).frame(height: 48)
    }
}

struct ProBadge: View {
    @ObservedObject var store: SnapshotStore
    let locale: String

    var body: some View {
        Group {
            switch store.entitlement {
            case .licensed:
                Label("PRO", systemImage: "crown.fill").foregroundStyle(Theme.goldText)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Theme.goldSoft, in: Capsule())
            case .trial(let until):
                Text(tr(locale, "试用剩 \(TrialCopy.daysLeft(until)) 天", "Trial · \(TrialCopy.daysLeft(until))d left"))
                    .foregroundStyle(Theme.goldText)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Theme.goldSoft, in: Capsule())
            case .free:
                Label("PRO", systemImage: "sparkles").foregroundStyle(Theme.onGold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.gold, in: Capsule())
            }
        }
        .font(Theme.captionStrong)
        .labelStyle(.titleAndIcon)
    }
}

enum TrialCopy {
    static func daysLeft(_ until: Date, now: Date = Date()) -> Int {
        max(1, Int(ceil(until.timeIntervalSince(now) / 86400)))
    }
}

struct HomeFooter: View {
    @ObservedObject var store: SnapshotStore
    let locale: String
    let open: (Page) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 6) {
                if store.isRefreshing {
                    Text(tr(locale, "正在检查…", "Checking…"))
                } else if let date = store.lastRun {
                    Text(tr(locale, "更新于 ", "Updated ")) + Text(date, style: .time)
                } else if store.lastError != nil {
                    Text(tr(locale, "读取失败，点 ↻ 重试", "Couldn't read logs. Tap ↻"))
                }
                Button { open(.howItWorks) } label: {
                    Label("0 token", systemImage: "lock.shield")
                }.buttonStyle(LinkButtonStyle(color: Theme.secondary, font: Theme.caption))
                Spacer()
                Button { open(.settings) } label: { Image(systemName: "gearshape") }
                    .buttonStyle(IconButtonStyle())
                    .help(tr(locale, "设置", "Settings"))
                    .keyboardShortcut(",", modifiers: .command)
            }
            .font(Theme.caption).foregroundStyle(Theme.secondary)
            .padding(.horizontal, Theme.page).frame(height: 40)
        }
    }
}

struct DataPage: View {
    let json: String
    var body: some View {
        Text(json.isEmpty ? "—" : json)
            .font(.system(size: 10, design: .monospaced))
            .textSelection(.enabled)
            .card()
    }
}

import SwiftUI

enum FirstPracticeBranch: String {
    case usableLogs, noLogs, unsupported, permissionDenied

    static func from(_ coverage: [String: SourceCoverage]?) -> Self {
        let sources = Array((coverage ?? [:]).values)
        if sources.contains(where: { $0.validUsageCount > 0 && [.ok, .partial].contains($0.status) }) { return .usableLogs }
        if sources.contains(where: { $0.status == .permissionDenied }) { return .permissionDenied }
        if sources.contains(where: { $0.status == .unsupported }) { return .unsupported }
        return .noLogs
    }

    func message(_ locale: String) -> String {
        switch self {
        case .usableLogs: return ""
        case .noLogs: return tr(locale, "还没找到 Claude Code 或 Codex 的使用记录。先用它们做一件小事，再回来检查。",
                                "No Claude Code or Codex records yet. Use one of them for something small, then check again.")
        case .unsupported: return tr(locale, "找到了记录，但这个版本的格式暂时读不了。", "Found records, but this format isn't supported yet.")
        case .permissionDenied: return tr(locale, "没有权限读取记录，稍后再试。", "Couldn't read the records. Try again later.")
        }
    }
}

struct OnboardingPage: View {
    @ObservedObject var store: SnapshotStore
    let locale: String
    @State private var started: Bool
    @State private var revealed = false

    init(store: SnapshotStore, locale: String, started: Bool = false) {
        self.store = store
        self.locale = locale
        _started = State(initialValue: started)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scanning: Bool { started && (store.isRefreshing || (store.snapshot == nil && store.lastError == nil)) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Group {
                if !started { welcome }
                else if scanning { scan }
                else if let snapshot = store.snapshot, store.firstPracticeBranch == .usableLogs, snapshot.hasEvaluableScores { reveal(snapshot) }
                else { empty }
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 24)
        }
        .animation(reduceMotion ? nil : Theme.motion, value: started)
        .animation(reduceMotion ? nil : Theme.motion, value: scanning)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            AppMark(size: 56)
            VStack(spacing: 8) {
                Text(tr(locale, "每天一招，365 天成为 AI 大师", "One skill a day. Master AI in 365 days."))
                    .font(.system(size: 22, weight: .bold)).multilineTextAlignment(.center)
                Text(tr(locale, "住在菜单栏里的 AI 教练\n给每天用 Claude Code 和 Codex 的你",
                        "A menu-bar coach for people who\nuse Claude Code and Codex every day"))
                    .font(Theme.body).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).lineSpacing(3)
            }
            VStack(alignment: .leading, spacing: 14) {
                promise("gauge.with.needle", tr(locale, "看清你的 AI 水平", "See your AI level"),
                        tr(locale, "一个分数、一个段位，和全球用户比", "One score, one rank, compared worldwide"))
                promise("sparkles", tr(locale, "每天学一招", "Learn one skill a day"),
                        tr(locale, "挑你还没用过的，用一次就自动点亮", "Picked from what you haven't used yet"))
                promise("chart.bar.fill", tr(locale, "看清这周用了多少", "Know your week"),
                        tr(locale, "折算用量、额度剩余、几天后重置", "Usage value, quota left, reset time"))
            }.card()
            Button { started = true; store.recheck() } label: { Text(tr(locale, "开始体检", "Check me")) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            Label(tr(locale, "只读本机日志 · 0 token · 不上传", "Local logs only · 0 tokens · nothing uploaded"), systemImage: "lock.shield")
                .font(Theme.caption).foregroundStyle(Theme.secondary)
        }
    }

    private func promise(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.goldText)
                .frame(width: 30, height: 30).background(Theme.goldSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.bodyStrong)
                Text(detail).font(Theme.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var scan: some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.regular)
            Text(tr(locale, "正在读你的本机记录…", "Reading your local records…")).font(Theme.headline)
            VStack(alignment: .leading, spacing: 8) {
                if let scan = store.recheckScan {
                    ForEach(Array(scan.lines.enumerated()), id: \.offset) { index, line in
                        Label(line.title(locale: locale), systemImage: index < scan.completed ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundStyle(index < scan.completed ? Theme.goodText : Theme.secondary)
                    }
                }
            }.font(Theme.body)
            Text(tr(locale, "全程在本机，不调用任何 AI。", "All on this Mac. No AI calls."))
                .font(Theme.caption).foregroundStyle(Theme.tertiary)
        }
    }

    private func reveal(_ snapshot: Snapshot) -> some View {
        let score = snapshot.overall?.score ?? 0
        let weakest = snapshot.dimensions?.filter { $0.score != nil }.min { $0.score! < $1.score! }
        return VStack(spacing: 18) {
            ScoreRing(score: score, size: 132, line: 12, font: Theme.number(48, .bold),
                      fraction: revealed || reduceMotion ? Double(score) / 100 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 1.0), value: revealed)
                .onAppear { revealed = true }
            VStack(spacing: 6) {
                Text(tr(locale, "你是「\(Rank.of(score).title(locale))」", "You're a \(Rank.of(score).title(locale))"))
                    .font(.system(size: 24, weight: .bold))
                Text(Rank.nextCaption(score, locale: locale)).font(Theme.body).foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                if let weakest, let value = weakest.score {
                    HStack {
                        Text(tr(locale, "最该补的一项", "Work on first")).font(Theme.caption).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(DimensionCopy.name(weakest, locale: locale)).font(Theme.bodyStrong)
                        Chip(text: "\(value)", tone: DimensionState(score: value).tone)
                    }
                }
                if let card = snapshot.book?.today {
                    Hairline()
                    HStack {
                        Text(tr(locale, "今日一招", "Today's skill")).font(Theme.caption).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(card.title).font(Theme.bodyStrong).lineLimit(1)
                    }
                }
            }.card()
            Button { store.dismissOnboarding() } label: { Text(tr(locale, "开始今天的修炼", "Start today")) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray").font(.system(size: 34)).foregroundStyle(Theme.tertiary)
            Text(store.lastError != nil ? tr(locale, "这次没读成功", "Couldn't read your records")
                 : tr(locale, "还没有可评估的记录", "Nothing to score yet")).font(Theme.title)
            Text(store.firstPracticeBranch == .usableLogs
                 ? tr(locale, "记录还不够算出分数，多用一两天再来。", "Not enough records to score yet. Come back in a day or two.")
                 : store.firstPracticeBranch.message(locale)).font(Theme.body).foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button { store.recheck() } label: { Text(tr(locale, "重新检查", "Check again")) }.buttonStyle(PrimaryButtonStyle())
            Button(tr(locale, "先逛逛", "Look around first")) { store.dismissOnboarding() }.buttonStyle(LinkButtonStyle(color: Theme.secondary))
        }
    }
}

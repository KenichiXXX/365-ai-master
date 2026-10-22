import SwiftUI

struct LocalValidation: Decodable {
    struct FirstFunnel: Decodable { let denominator, started, observed, selfReported, reused: Int }
    struct Funnel: Decodable { let attempts, observed, selfReported, reused: Int }
    struct Rate: Decodable { let numerator, denominator: Int }
    struct Return: Decodable { let status: String; let denominator, foreground, practice: Int }
    let cohort: String
    let installationDate: String?
    let measurementStart, windowStart, windowEnd: String
    let windowDays: Int
    let truncated, measurementReset: Bool
    let counts, expiredCounts: [String: Int]
    let funnel: Funnel
    let firstPracticeFunnel: FirstFunnel
    let reuseRate: Rate
    let observationRate: Rate
    let d1, d7: Return
    let unsupportedSources, sourceDenominator, trialStarts: Int
    let activationStatus, renewalStatus: String
    let labels: [String: String]
}

enum LocalEvent: String {
    case foregroundOpen = "foreground_open", sharePreview = "share_preview", shareCopy = "share_copy"
    case shareSave = "share_save", feedbackCopy = "feedback_copy", trialStart = "trial_start"
    case activation, renewal, checkoutReturn = "checkout_return"
}

enum LocalEventResult: String { case ok, importedVerified = "imported_verified", active, expired, pending, unavailable, revoked }

enum FeedbackCoverage: String, Codable, CaseIterable {
    case ok, notDetected = "not_detected", noLogs = "no_logs", permissionDenied = "permission_denied", unsupported, partial
}

enum FeedbackReason: String, Codable, CaseIterable {
    case unspecified, unclear, unsupportedTool = "unsupported_tool", noProject = "no_project", notNow = "not_now"
    func title(_ locale: String) -> String {
        let copy: [Self: [String]] = [.unspecified: ["未选择", "Not selected"], .unclear: ["说明不清楚", "Unclear instructions"],
            .unsupportedTool: ["工具不支持", "Unsupported tool"], .noProject: ["没有项目", "No project"], .notNow: ["暂不练习", "Not now"]]
        return copy[self]![locale == "zh" ? 0 : 1]
    }
}

struct FeedbackDraft {
    let appVersion: String
    let schema: Int
    let coverage: [String: Int]
    let attempts: Int
    let observations: Int
    var reason: FeedbackReason = .unspecified { didSet { copyText = nil } }
    private(set) var copyText: String?

    init(appVersion: String, schema: Int, coverage: [FeedbackCoverage: Int], attempts: Int, observations: Int) {
        self.appVersion = appVersion.range(of: #"^\d{1,4}(\.\d{1,4}){0,3}$"#, options: .regularExpression) != nil ? appVersion : "unknown"
        self.schema = max(1, min(schema, 3))
        self.coverage = Dictionary(uniqueKeysWithValues: coverage.map { ($0.key.rawValue, max(0, $0.value)) })
        self.attempts = max(0, attempts)
        self.observations = max(0, observations)
    }

    mutating func preview() {
        struct Payload: Encodable {
            let appVersion: String
            let schema: Int
            let coverage: [String: Int]
            let reason: FeedbackReason
            let attempts, observations: Int
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let payload = Payload(appVersion: appVersion, schema: schema, coverage: coverage, reason: reason,
                              attempts: attempts, observations: observations)
        copyText = (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func from(_ snapshot: Snapshot) -> Self {
        var coverage: [FeedbackCoverage: Int] = [:]
        for row in snapshot.coverage?.values ?? [:].values {
            if let status = FeedbackCoverage(rawValue: row.status.rawValue) { coverage[status, default: 0] += 1 }
        }
        return Self(appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    schema: snapshot.schema, coverage: coverage,
                    attempts: snapshot.localValidation?.funnel.attempts ?? 0,
                    observations: snapshot.localValidation?.funnel.observed ?? 0)
    }
}

struct LocalValidationView: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    @State private var feedback: FeedbackDraft
    init(snapshot: Snapshot, store: SnapshotStore) {
        self.snapshot = snapshot
        self.store = store
        _feedback = State(initialValue: FeedbackDraft.from(snapshot))
    }
    private var locale: String { snapshot.locale ?? "en" }
    private func text(_ en: String, _ chinese: String) -> String { tr(locale, chinese, en) }
    private func status(_ value: String) -> String {
        let copy = ["new_installation": ["新安装观察组", "New installation cohort"],
            "post_upgrade": ["升级后测量组，安装日期未知", "Post-upgrade measurement cohort; installation date unknown"],
            "unknown_installation": ["安装日期未知", "Installation date unknown"],
            "outside_window": ["超出保留窗口", "Outside retained window"],
            "imported_verified": ["导入激活码已验证，不代表新购买", "Imported key verified; not a new purchase"],
            "active": ["本地权益有效", "Local entitlement active"], "expired": ["本地权益已过期", "Local entitlement expired"],
            "revoked": ["授权已撤销", "Authorization revoked"],
            "pending": ["待核验", "Pending verification"], "unavailable": ["未知或不可用", "Unknown or unavailable"]]
        if value == "not_yet" { return shareCopy("Observation date has not arrived", locale) }
        return copy[value]?[locale == "zh" ? 0 : 1] ?? value
    }

    var body: some View {
        VStack(spacing: Theme.gap) {
            VStack(alignment: .leading, spacing: 10) {
                Text(text("Stuck somewhere? Pick a reason, preview what would be shared, then copy it into an email or issue. Nothing is sent automatically.",
                          "卡住了？选一个原因，预览要分享的内容，再复制到邮件或 issue 里。不会自动发送任何东西。"))
                    .font(Theme.body).fixedSize(horizontal: false, vertical: true)
                Picker(text("Reason", "原因"), selection: $feedback.reason) {
                    ForEach(FeedbackReason.allCases, id: \.self) { Text($0.title(locale)).tag($0) }
                }.font(Theme.body)
                Button(shareCopy("Preview", locale)) { feedback.preview() }.buttonStyle(SecondaryButtonStyle())
                if let copy = feedback.copyText {
                    Text(copy).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    CopyButton(prompt: copy, title: shareCopy("Copy sanitized feedback", locale), locale: locale,
                               copiedTitle: shareCopy("Copied, not published", locale),
                               onCopied: { store.recordLocalEvent(.feedbackCopy) }, primary: true)
                }
            }.card()
            DisclosureGroup {
                diagnostics.padding(.top, 8)
            } label: {
                Text(shareCopy("Local validation", locale)).font(Theme.caption).foregroundStyle(Theme.secondary)
            }.padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shareCopy("This installation only. Nothing is reported", locale))
            if store.localEventError {
                Text(text("Some local events could not be recorded. Counts may be incomplete.", "部分本机事件未能记录，计数可能不完整。"))
            }
            if let data = snapshot.localValidation {
                Text(status(data.cohort))
                if data.measurementReset {
                    Text(text("Local diagnostics were unreadable. Measurement restarted; installation date is unknown.",
                              "本机诊断记录不可读，已重新开始测量；安装日期未知。"))
                }
                Text(text("Measurement started: ", "测量开始：") + DisplayDate.short(data.measurementStart, locale: locale))
                Text(text("Observation window: ", "观察窗口：") + DisplayDate.short(data.windowStart, locale: locale) + " → " + DisplayDate.short(data.windowEnd, locale: locale))
                if data.truncated {
                    Text(text("Older or excess rows were aggregated. Retained window only.", "较早或超量记录已汇总，以下仅计保留窗口。"))
                }
                Text(text("Attempts / observed / self-reported / reused skills: ", "尝试 / 已观察 / 自报 / 跨日复用技能：")
                     + "\(data.funnel.attempts) / \(data.funnel.observed) / \(data.funnel.selfReported) / \(data.funnel.reused)")
                Text(text("Observed attempts / all attempts: ", "有新观察的尝试 / 全部尝试：") +
                     "\(data.observationRate.numerator)/\(data.observationRate.denominator)")
                ForEach([("D1", data.d1), ("D7", data.d7)], id: \.0) { name, value in
                    if value.status == "observed" {
                        Text(name + text(" foreground return / eligible installation: ", " 前台返回 / 可观察安装：") + "\(value.foreground)/\(value.denominator)")
                    } else { Text(name + " · " + status(value.status)) }
                }
                Text(text("Unavailable coverage / selected sources: ", "覆盖不可用 / 已选来源：") + "\(data.unsupportedSources)/\(data.sourceDenominator)")
                Text(text("Imported activation: ", "导入激活：") + status(data.activationStatus))
                Text(text("Local renewal: ", "本地续订：") + status(data.renewalStatus))
                Text(text("New purchases unknown. Browser opens are not payments. This is not a population retention rate or causal lift.",
                          "新购买未知，打开浏览器不计为付款。这里不代表群体留存率或因果提升。"))
            } else { Text(text("No local measurement available", "暂无本机测量记录")) }
        }
        .font(Theme.caption).foregroundStyle(Theme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

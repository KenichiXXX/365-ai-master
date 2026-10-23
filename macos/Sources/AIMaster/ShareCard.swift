import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Titles are reviewed bundled copy; downloaded titles never enter an export.
enum ReviewedCapability: String, Codable, CaseIterable {
    case rules_file, web_search, web_fetch, plan_mode, todo_list, ask_first, subagent, light_model, effort_up, first_skill, mcp, hook, compact, worktree, codex_agents, init_cmd, clear_session, resume, at_mention, paste_image, headless, custom_command, review_diff, permissions

    func title(locale: String) -> String {
        let titles: [Self: [String]] = [
            .rules_file: ["写一份 CLAUDE.md", "Write a CLAUDE.md"],
            .web_search: ["让 AI 联网搜索", "Let the AI search the web"],
            .web_fetch: ["让 AI 读一个网页", "Have the AI read a page"],
            .plan_mode: ["Plan 模式：先出方案再动手", "Plan mode: plan before acting"],
            .todo_list: ["让 AI 列任务清单", "Let the AI keep a to-do list"],
            .ask_first: ["让 AI 先问你", "Let the AI ask first"],
            .subagent: ["子代理：同时开几条线", "Sub-agents: work in parallel"],
            .light_model: ["机械活交给轻量模型", "Give chores to a light model"],
            .effort_up: ["难题调高推理强度", "Raise reasoning effort for hard problems"],
            .first_skill: ["用起第一个 skill", "Use your first skill"],
            .mcp: ["用 MCP 连接外部工具", "Connect tools with MCP"],
            .hook: ["Hook：让固定动作自动发生", "Hooks: automate the routine"],
            .compact: ["长对话压缩一下", "Compact long chats"],
            .worktree: ["用 worktree 并行开发", "Parallel work with worktrees"],
            .codex_agents: ["给 Codex 写 AGENTS.md", "Write an AGENTS.md for Codex"],
            .init_cmd: ["/init 自动生成说明书", "Generate a brief with /init"],
            .clear_session: ["一个任务一个会话", "One task per session"],
            .resume: ["接着上次的会话", "Pick up where you left off"],
            .at_mention: ["用 @ 引用文件", "Reference files with @"],
            .paste_image: ["贴截图让 AI 看", "Paste a screenshot"],
            .headless: ["非交互模式跑批量活", "Headless mode for batch jobs"],
            .custom_command: ["自定义斜杠命令", "Custom slash commands"],
            .review_diff: ["让 AI 改完自查", "Have the AI review its own diff"],
            .permissions: ["设好常用权限", "Set up permissions"]
        ]
        return titles[self]![locale == "zh" ? 0 : 1]
    }
}

enum ShareEvidence: String, Codable {
    case ready, started, log_observed, reuse, self_reported, historical, configuration
    func title(locale: String) -> String {
        let copy: [Self: [String]] = [
            .ready: ["待实践", "Ready to practise"], .started: ["已开始", "Started"],
            .log_observed: ["日志已观察", "Observed in logs"], .reuse: ["跨日复用", "Distinct-day reuse"],
            .self_reported: ["已尝试（自报）", "Tried (self-reported)"],
            .historical: ["历史记录", "Historical record"], .configuration: ["配置存在", "Configuration found"]]
        return copy[self]![locale == "zh" ? 0 : 1]
    }
}

struct SharePeriod: Encodable {
    let start: String
    let end: String
    init(start: String, end: String) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let first = formatter.date(from: start), formatter.string(from: first) == start,
              let last = formatter.date(from: end), formatter.string(from: last) == end, first <= last else {
            throw EngineError.badJSON
        }
        self.start = start
        self.end = end
    }
}

struct ShareScore: Encodable {
    let value: Int
    let coverage: SharePeriod
    init(value: Int, coverage: SharePeriod) throws {
        guard (0...100).contains(value) else { throw EngineError.badJSON }
        self.value = value
        self.coverage = coverage
    }
}

struct ShareCardInput: Encodable {
    struct Entry: Encodable {
        let capability: ReviewedCapability
        let evidence: ShareEvidence
    }
    let period: SharePeriod
    let capabilities: [Entry]
    var score: ShareScore? = nil

    static func from(_ snapshot: Snapshot, includeScore: Bool) -> Self? {
        guard let generated = snapshot.generatedAt,
              let period = try? SharePeriod(start: String((snapshot.localValidation?.windowStart ?? generated).prefix(10)),
                                           end: String(generated.prefix(10))) else { return nil }
        let entries = ReviewedCapability.allCases.compactMap { capability -> Entry? in
            guard let card = snapshot.book?.cards.first(where: { $0.id == capability.rawValue }),
                  let evidence = ShareEvidence(rawValue: card.evidenceKind ?? "ready"),
                  evidence != .ready else { return nil }
            return Entry(capability: capability, evidence: evidence)
        }
        var result = Self(period: period, capabilities: entries)
        if includeScore, snapshot.hasEvaluableScores, let value = snapshot.overall?.score,
           let starts = snapshot.coverage?.values.compactMap(\.startUtc), let first = starts.min(),
           let ends = snapshot.coverage?.values.compactMap(\.endUtc), let last = ends.max(),
           let coverage = try? SharePeriod(start: String(first.prefix(10)), end: String(last.prefix(10))) {
            result.score = try? ShareScore(value: value, coverage: coverage)
        }
        return result
    }
}

struct ShareCardGraphic: View {
    let input: ShareCardInput
    let locale: String

    private let night = Theme.color(0x17181E)
    private let card = Theme.color(0x202129)
    private let gold = Theme.color(0xBBAFF3)
    private let ink = Theme.color(0xF4F4F8)
    private let muted = Theme.color(0xA6A7B7)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                AppMark(size: 30)
                Text("365 AI Master").font(.system(size: 17, weight: .semibold)).foregroundStyle(ink)
                Spacer()
                Text(DisplayDate.short(input.period.end, locale: locale, year: true))
                    .font(.system(size: 13)).foregroundStyle(muted)
            }
            HStack(alignment: .center, spacing: 22) {
                if let score = input.score {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 12)
                        Circle().trim(from: 0, to: Double(score.value) / 100)
                            .stroke(gold, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(score.value)").font(.system(size: 46, weight: .bold)).foregroundStyle(ink)
                    }.frame(width: 128, height: 128)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(input.score.map { tr(locale, "AI \(Rank.of($0.value).title(locale))", "AI \(Rank.of($0.value).title(locale))") }
                         ?? tr(locale, "我的 AI 修炼", "My AI practice"))
                        .font(.system(size: 34, weight: .bold)).foregroundStyle(gold)
                    Text(tr(locale, "已点亮 \(input.capabilities.count) 招", "\(input.capabilities.count) skills lit"))
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(ink)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(input.capabilities.prefix(8).enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(gold)
                        Text(entry.capability.title(locale: locale)).font(.system(size: 15)).foregroundStyle(ink)
                        Spacer()
                        Text(entry.evidence.title(locale: locale)).font(.system(size: 12)).foregroundStyle(muted)
                    }
                }
                if input.capabilities.count > 8 {
                    Text(tr(locale, "还有 \(input.capabilities.count - 8) 招…", "+\(input.capabilities.count - 8) more…"))
                        .font(.system(size: 13)).foregroundStyle(muted)
                }
                if input.capabilities.isEmpty {
                    Text(tr(locale, "第一招正在路上", "First skill on the way")).font(.system(size: 15)).foregroundStyle(muted)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(tr(locale, "每天一招，365 天成为 AI 大师", "One AI skill a day. Master AI in 365 days."))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
                Text(shareCopy("Local practice record, not a certification of ability", locale))
                    .font(.system(size: 11)).foregroundStyle(muted)
            }
        }
        .padding(32)
        .frame(width: 560, alignment: .leading)
        .background(night)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: locale))
    }
}

@MainActor
enum ShareCardRenderer {
    static func png(_ input: ShareCardInput, locale: String) throws -> Data {
        let renderer = ImageRenderer(content: ShareCardGraphic(input: input, locale: locale))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { throw EngineError.badJSON }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw EngineError.badJSON
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw EngineError.badJSON }
        return try pixelsOnly(data as Data)
    }

    private static func pixelsOnly(_ png: Data) throws -> Data {
        var result = Data(png.prefix(8))
        var offset = 8
        let allowed = Set(["IHDR", "PLTE", "IDAT", "IEND", "tRNS"])
        while offset + 12 <= png.count {
            let length = png[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            let end = offset + length + 12
            guard end <= png.count,
                  let name = String(data: png.subdata(in: (offset + 4)..<(offset + 8)), encoding: .ascii) else {
                throw EngineError.badJSON
            }
            if allowed.contains(name) { result.append(png.subdata(in: offset..<end)) }
            offset = end
        }
        guard offset == png.count else { throw EngineError.badJSON }
        return result
    }

    static func save(_ png: Data, chooseURL: () -> URL?) throws -> Bool {
        guard let url = chooseURL() else { return false }
        try png.write(to: url, options: .atomic)
        return true
    }
}

func shareCopy(_ key: String, _ locale: String) -> String {
    let language = locale == "zh" ? "zh-Hans" : "en"
    let bundle = Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
    return NSLocalizedString(key, bundle: bundle, comment: "")
}

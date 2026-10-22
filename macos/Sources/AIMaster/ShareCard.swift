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
    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.grid) {
                Text(shareCopy("Share my practice", locale)).font(Theme.title)
                Text(DisplayDate.short(input.period.start, locale: locale, year: true) + " – " + DisplayDate.short(input.period.end, locale: locale, year: true)).font(Theme.body)
                ForEach(Array(input.capabilities.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: Theme.grid) {
                        Text(entry.capability.title(locale: locale)).font(Theme.title)
                        Text(entry.evidence.title(locale: locale)).font(Theme.body).foregroundStyle(Theme.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                }
                if input.capabilities.isEmpty {
                    Text(locale == "zh" ? "等待练习记录" : "Waiting for practice records")
                }
                if let score = input.score {
                    Text((locale == "zh" ? "已知分数 " : "Known score ") + String(score.value) + "/100")
                    Text(DisplayDate.short(score.coverage.start, locale: locale, year: true) + " – " + DisplayDate.short(score.coverage.end, locale: locale, year: true)).font(Theme.label)
                }
                ThemeRule()
                Text(shareCopy("Local practice record, not a certification of ability", locale))
                    .font(Theme.label).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.fixedInk)
            .padding(Theme.grid * 2).frame(width: 560, alignment: .leading).background(Theme.fixedPaper)
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: locale))
        }.bauhausTheme()
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

struct ShareCard: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    @Environment(\.dismiss) private var dismiss
    @State private var includeScore = false
    @State private var preview: Data?
    @State private var message: String?
    private var locale: String { snapshot.locale ?? "en" }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Theme.grid) {
                Text(shareCopy("Share my practice", locale)).font(Theme.title)
                Toggle(shareCopy("Include score and coverage period", locale), isOn: $includeScore)
                    .disabled(!snapshot.hasEvaluableScores)
                    .onChange(of: includeScore) { _ in preview = nil; message = nil }
                Button(shareCopy("Preview", locale)) {
                    do {
                        guard let input = ShareCardInput.from(snapshot, includeScore: includeScore) else { throw EngineError.badJSON }
                        preview = try ShareCardRenderer.png(input, locale: locale)
                        message = nil
                        store.recordLocalEvent(.sharePreview)
                    } catch { message = shareCopy("Refresh failed", locale) }
                }
                if let preview, let image = NSImage(data: preview) {
                    ScrollView { Image(nsImage: image).resizable().scaledToFit() }.frame(maxHeight: 460)
                    HStack {
                        Button(shareCopy("Copy image", locale)) {
                            NSPasteboard.general.clearContents()
                            if NSPasteboard.general.setData(preview, forType: .png) {
                                store.recordLocalEvent(.shareCopy)
                                message = shareCopy("Copied, not published", locale)
                            }
                        }
                        Button(shareCopy("Save image", locale)) {
                            do {
                                if try ShareCardRenderer.save(preview, chooseURL: {
                                    let panel = NSSavePanel()
                                    panel.allowedContentTypes = [.png]
                                    panel.nameFieldStringValue = "practice.png"
                                    return panel.runModal() == .OK ? panel.url : nil
                                }) { store.recordLocalEvent(.shareSave) }
                            } catch { message = shareCopy("Refresh failed", locale) }
                        }
                    }
                }
                if let message { Text(message).font(Theme.label) }
                Button(shareCopy("Done", locale)) { dismiss() }
            }.padding(Theme.grid * 2).frame(width: 420)
        }.bauhausTheme()
    }
}

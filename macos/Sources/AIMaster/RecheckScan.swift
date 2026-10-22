import Foundation

struct RecheckScan {
    enum Line: Equatable {
        case tool(String)
        case score

        func title(locale: String) -> String {
            let zh = locale == "zh"
            switch self {
            case .score: return zh ? "计算四维分…" : "Calculating four scores…"
            case .tool(let id):
                let name = ["claude_code": "Claude Code", "codex": "Codex", "gemini_cli": "Gemini CLI",
                            "opencode": "OpenCode", "qwen_code": "Qwen Code"][id] ?? id
                return zh ? "读取 \(name) 记录…" : "Reading \(name) records…"
            }
        }
    }

    let lines: [Line]
    var completed = 0

    static func lines(snapshot: Snapshot?, enabledTools: [String]) -> [Line] {
        (snapshot?.tools ?? []).filter { $0.detected && enabledTools.contains($0.tool) }
            .map { .tool($0.tool) } + [.score]
    }
}

struct ScoreChange {
    let delta: Int
    let date: Date

    func isVisible(at now: Date) -> Bool { (0..<5).contains(now.timeIntervalSince(date)) }

    func caption(locale: String) -> String {
        let number = delta > 0 ? "+\(delta)" : "−\(-delta)"
        return locale == "zh" ? "比上次 \(number)" : "\(number) since last check"
    }
}

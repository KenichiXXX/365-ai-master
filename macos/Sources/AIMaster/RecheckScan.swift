import SwiftUI

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

struct ScoreCountUp {
    let score: Int?
    let startedAt: Date?

    func value(at now: Date, reduceMotion: Bool) -> Int? {
        guard !reduceMotion, let startedAt, let score else { return score }
        let progress = min(1, max(0, now.timeIntervalSince(startedAt) / 0.7))
        return Int((Double(score) * progress).rounded())
    }
}

struct RecheckScoreView: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        Group {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !needsFrames)) { context in
                VStack(spacing: Theme.grid) {
                    if let scan = store.recheckScan {
                        Circle().trim(from: 0, to: 0.7)
                            .stroke(Theme.blue, style: StrokeStyle(lineWidth: 12, lineCap: .butt))
                            .frame(width: 125, height: 125)
                            .rotationEffect(.degrees(reduceMotion ? -90 : context.date.timeIntervalSinceReferenceDate * 240))
                            .accessibilityLabel(snapshot.locale == "zh" ? "正在扫描" : "Checking")
                        VStack(alignment: .leading, spacing: Theme.grid) {
                            ForEach(scan.lines.indices, id: \.self) { index in
                                Label(scan.lines[index].title(locale: snapshot.locale ?? store.locale),
                                      systemImage: index < scan.completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(index < scan.completed ? Theme.ink : Theme.secondary)
                            }
                        }.font(Theme.body)
                    } else {
                        Circle().fill(Theme.blue).frame(width: 128, height: 128)
                            .overlay {
                                Text(ScoreCountUp(score: snapshot.overall?.score, startedAt: settled ? nil : store.recheckCompletedAt)
                                    .value(at: context.date, reduceMotion: reduceMotion).map(String.init) ?? "—")
                                    .font(Theme.score).foregroundStyle(.white).monospacedDigit()
                            }
                            .accessibilityLabel(snapshot.locale == "zh" ? "总分" : "Score")
                            .accessibilityValue(snapshot.overall?.score.map(String.init) ?? "—")
                        if !settled, let change = store.scoreChange, change.isVisible(at: context.date) {
                            Text(change.caption(locale: snapshot.locale ?? store.locale))
                                .font(Theme.body).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            .task(id: store.recheckCompletedAt) {
                settled = false
                guard let date = store.recheckCompletedAt else { return }
                let remaining = max(0, 5 - Date().timeIntervalSince(date))
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                guard !Task.isCancelled else { return }
                settled = true
            }
        }.bauhausTheme()
    }

    private var needsFrames: Bool {
        if store.recheckScan != nil { return !reduceMotion }
        return store.recheckCompletedAt != nil && !settled
    }
}

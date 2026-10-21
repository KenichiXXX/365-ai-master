import SwiftUI
import AppKit

struct CopyFeedback {
    private(set) var copiedAt: Date?

    mutating func markCopied(at date: Date = Date()) { copiedAt = date }

    func isCopied(at date: Date = Date()) -> Bool {
        guard let copiedAt else { return false }
        return date.timeIntervalSince(copiedAt) < 1.5
    }
}

struct CopyButton: View {
    let prompt: String
    let title: String
    let locale: String
    var copiedTitle: String? = nil
    var onCopied: (() -> Void)? = nil
    @State private var feedback = CopyFeedback()
    @State private var copied = false

    var body: some View {
        Button(copied ? (copiedTitle ?? (locale == "zh" ? "已复制 ✓" : "Copied ✓")) : title) {
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(prompt, forType: .string) {
                feedback.markCopied()
                copied = true
                onCopied?()
            }
        }
        .task(id: feedback.copiedAt) {
            guard feedback.copiedAt != nil else { return }
            do { try await Task.sleep(nanoseconds: 1_500_000_000) }
            catch { return }
            copied = feedback.isCopied()
        }
    }
}

import SwiftUI
import AppKit

struct SharePage: View {
    let snapshot: Snapshot
    @ObservedObject var store: SnapshotStore
    let locale: String
    @State private var includeScore = true
    @State private var png: Data?
    @State private var message: String?

    var body: some View {
        VStack(spacing: Theme.gap) {
            if let png, let image = NSImage(data: png) {
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            HStack {
                Text(tr(locale, "带上分数和段位", "Include score and rank")).font(Theme.body)
                Spacer()
                Toggle("", isOn: $includeScore).labelsHidden()
            }
            .disabled(!snapshot.hasEvaluableScores)
            .card()
            HStack(spacing: 8) {
                Button { copy() } label: { Label(tr(locale, "复制图片", "Copy image"), systemImage: "doc.on.doc") }
                    .buttonStyle(PrimaryButtonStyle())
                Button { save() } label: { Label(tr(locale, "保存", "Save"), systemImage: "square.and.arrow.down") }
                    .buttonStyle(SecondaryButtonStyle())
            }.disabled(png == nil)
            Text(message ?? tr(locale, "图片只在本机生成，发不发、发到哪由你决定。", "The image is made on this Mac. You decide where it goes."))
                .font(Theme.caption).foregroundStyle(Theme.secondary)
        }
        .onAppear(perform: render)
        .onChange(of: includeScore) { _ in render() }
    }

    private func render() {
        guard let input = ShareCardInput.from(snapshot, includeScore: includeScore && snapshot.hasEvaluableScores),
              let data = try? ShareCardRenderer.png(input, locale: locale) else {
            message = tr(locale, "这次没生成成功", "Couldn't make the image")
            return
        }
        png = data
        message = nil
        store.recordLocalEvent(.sharePreview)
    }

    private func copy() {
        guard let png else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setData(png, forType: .png) {
            store.recordLocalEvent(.shareCopy)
            message = tr(locale, "已复制，还没有发出去", "Copied. Nothing has been posted")
        }
    }

    private func save() {
        guard let png else { return }
        do {
            if try ShareCardRenderer.save(png, chooseURL: {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                panel.nameFieldStringValue = "365-ai-master.png"
                return panel.runModal() == .OK ? panel.url : nil
            }) { store.recordLocalEvent(.shareSave) }
        } catch { message = tr(locale, "保存失败", "Couldn't save") }
    }
}

import SwiftUI

enum AnalysisPromise {
    static let caption = "0 token"
    static func title(locale: String) -> String { locale == "zh" ? "怎么算的" : "How it works" }
    static func lines(locale: String) -> [String] {
        locale == "zh"
            ? ["只读本机日志", "规则计算，不调用任何 AI", "不消耗你的 token 额度", "不上传（除非你开启排名/榜单下载）"]
            : ["Reads local logs only", "Uses rules, without calling AI", "Uses none of your token quota",
               "No uploads (unless you enable rankings / leaderboard downloads)"]
    }
}

struct AnalysisPromiseSheet: View {
    let locale: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) {
            Text(AnalysisPromise.title(locale: locale)).font(Theme.title)
            ForEach(AnalysisPromise.lines(locale: locale), id: \.self) { line in
                Text(line).font(Theme.body).fixedSize(horizontal: false, vertical: true)
            }
            Button(locale == "zh" ? "知道了" : "Got it") { dismiss() }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(Theme.cardPadding).frame(width: 380).bauhausTheme()
    }
}

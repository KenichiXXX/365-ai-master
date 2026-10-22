import SwiftUI

struct ProSheet: View {
    @ObservedObject var store: SnapshotStore
    let zh: Bool
    let close: () -> Void

    var body: some View {
        VStack(spacing: Theme.sectionGap) {
            ScrollView {
                ProSettingsSection(store: store, zh: zh)
                    .padding(Theme.pagePadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(zh ? "完成" : "Done", action: close)
                .padding(.bottom, Theme.pagePadding)
        }
        .frame(width: 440, height: 660)
        .background(MasterWindowBackground())
        .bauhausTheme()
    }
}

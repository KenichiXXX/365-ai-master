import SwiftUI
import AppKit

struct ProPage: View {
    @ObservedObject var store: SnapshotStore
    let locale: String
    @State private var activationKey = ""
    @State private var showActivation = false
    @State private var showTerms = false
    private var zh: Bool { locale == "zh" }

    var body: some View {
        VStack(spacing: Theme.gap) {
            hero
            benefits
            if store.license == nil { offer }
            if store.signedLicense != nil || store.renewalState == .pending { licenseStatus }
            activation
            DisclosureGroup(isExpanded: $showTerms) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(PurchaseTerms.lines(locale: locale, option: store.selectedPurchaseOption ?? PurchaseOption.ordered(zh: zh)[0]),
                            id: \.self) { Text(verbatim: $0).font(Theme.caption).foregroundStyle(Theme.secondary) }
                    CourseSourceField(store: store, locale: locale)
                    Toggle(t("Refresh license automatically"), isOn: $store.autoRefreshLicense).font(Theme.caption)
                    Text(t("Automatic key refresh sends your license ID and signed activation key to the license service, never usage records"))
                        .font(Theme.caption).foregroundStyle(Theme.tertiary)
                }.padding(.top, 8)
            } label: {
                Text(tr(locale, "购买条款", "Purchase terms")).font(Theme.caption).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            AppMark(size: 44)
            Text(store.license != nil ? tr(locale, "Pro 已开启", "Pro is on") : tr(locale, "解锁完整的 365 天修炼", "Unlock the full 365-day path"))
                .font(Theme.title)
            Text(tr(locale, "每天一招，看得见自己在变强。", "One skill a day, and proof you're getting better."))
                .font(Theme.body).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }

    private var benefits: some View {
        let total = store.snapshot?.book?.total ?? 24
        return VStack(alignment: .leading, spacing: 12) {
            benefit("map.fill", tr(locale, "全部 \(total) 招，想学哪招学哪招", "All \(total) skills, in any order"),
                    tr(locale, "免费版只开放入门路线", "Free covers the Basics path"))
            benefit("chart.line.uptrend.xyaxis", tr(locale, "每周复盘 + 30 天成长曲线", "Weekly review + 30-day curve"),
                    tr(locale, "看清分数为什么涨、为什么跌", "See why your score moved"))
            benefit("globe.asia.australia.fill", tr(locale, "四项能力的全球排名", "Global rank on each skill"),
                    tr(locale, "知道自己哪一项最拿得出手", "Know where you stand out"))
            benefit("list.number", tr(locale, "完整榜单 Top 20 + 产品榜", "Full Top 20 + products"),
                    tr(locale, "每天更新的技能和工具", "Skills and tools, updated daily"))
        }.card()
    }

    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.goldText)
                .frame(width: 30, height: 30).background(Theme.goldSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.bodyStrong)
                Text(detail).font(Theme.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$12").font(Theme.number(34, .bold))
                Text(tr(locale, "/ 年", "/ year")).font(Theme.headline).foregroundStyle(Theme.secondary)
                Spacer()
                Chip(text: tr(locale, "创始价 · 约每月 $1", "Founding price · ~$1/mo"), tone: .gold)
            }
            trial
            PurchaseOptionsList(store: store, locale: locale)
        }.card(fill: Theme.goldSoft, stroke: Theme.gold.opacity(0.35))
    }

    @ViewBuilder
    private var trial: some View {
        switch store.trialStatus {
        case .eligible:
            Button { store.startProTrial() } label: { Text(tr(locale, "免费试用 14 天", "Start 14-day free trial")) }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("pro-start-trial")
            HStack(spacing: 0) {
                timeline("1", tr(locale, "今天", "Today"), tr(locale, "全部解锁", "Everything unlocks"))
                timeline("2", tr(locale, "14 天内", "14 days"), tr(locale, "随便用", "Use it all"))
                timeline("3", tr(locale, "到期", "Then"), tr(locale, "自动回到免费版", "Back to Free"))
            }
            Text(tr(locale, "不绑卡，不会自动扣款，历史记录都保留。", "No card, no automatic charge. Your history stays."))
                .font(Theme.caption).foregroundStyle(Theme.secondary)
        case .active(let until):
            Label(tr(locale, "试用中，还剩 \(TrialCopy.daysLeft(until)) 天", "Trial active · \(TrialCopy.daysLeft(until)) days left"),
                  systemImage: "hourglass").font(Theme.bodyStrong).foregroundStyle(Theme.goldText)
        case .expired(let reason):
            Text(reason == .clockRollback ? tr(locale, "设备时间被调回过，试用已结束。", "The clock moved backwards, so the trial ended.")
                 : tr(locale, "试用已结束，历史记录都在。", "Trial ended. Your history is safe."))
                .font(Theme.body).foregroundStyle(Theme.secondary)
        }
    }

    private func timeline(_ number: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.captionStrong)
            Text(detail).font(Theme.caption).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(number + " " + title + " " + detail)
    }

    private var licenseStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let license = store.signedLicense {
                Label(tr(locale, "激活码有效期至 ", "Key valid through ") + DisplayDate.short(license.exp, locale: locale, year: true),
                      systemImage: "checkmark.seal.fill").font(Theme.bodyStrong).foregroundStyle(Theme.goodText)
                if case .active(_, let end) = store.renewalState {
                    Text(verbatim: t("Verified paid period ends {date}").replacingOccurrences(of: "{date}", with: DisplayDate.short(end, locale: locale, year: true)))
                        .font(Theme.caption).foregroundStyle(Theme.secondary)
                }
            }
            Text(store.signedLicense?.isOneTimeAnnual == true && store.renewalState != .revoked
                 ? tr(locale, "一次付一年，不自动续费。到期后需要再买。", "One year, no auto-renewal. Buy again after it ends.")
                 : t(store.renewalState.messageKey))
                .font(Theme.caption).foregroundStyle(Theme.secondary)
            HStack(spacing: 8) {
                if store.signedLicense != nil {
                    Button(t("Refresh activation key")) { store.refreshLicense(explicit: true) }
                        .buttonStyle(SecondaryButtonStyle()).disabled(store.licenseRefreshTask != nil)
                }
                if let url = store.purchaseConfiguration.managementURL {
                    Button(t("Manage or cancel subscription")) { NSWorkspace.shared.open(url) }.buttonStyle(SecondaryButtonStyle())
                }
            }
            if let days = store.oneTimeRenewalDays {
                Button(OneTimeRenewal.message(days: days, zh: zh)) { store.openOneTimeRenewal() }.buttonStyle(PrimaryButtonStyle())
            }
        }.card()
    }

    private var activation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(Theme.motion) { showActivation.toggle() } } label: {
                Text(tr(locale, "已有激活码？", "Have an activation key?"))
            }.buttonStyle(LinkButtonStyle(color: Theme.secondary, font: Theme.body))
                .accessibilityIdentifier("pro-enter-key")
            if showActivation {
                HStack(spacing: 8) {
                    TextField("AIM1…", text: $activationKey)
                        .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.hairline))
                    Button(tr(locale, "激活", "Activate")) {
                        if store.activateLicense(activationKey) { activationKey = "" }
                    }.buttonStyle(PrimaryButtonStyle(expand: false)).disabled(activationKey.isEmpty)
                }
                if let error = store.licenseError {
                    Label(error.message(locale: locale), systemImage: "exclamationmark.triangle")
                        .font(Theme.caption).foregroundStyle(Theme.lowText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
    }

    private func t(_ key: String) -> String { PurchaseTerms.localized(key, locale: locale) }
}

struct PurchaseOptionsList: View {
    @ObservedObject var store: SnapshotStore
    let locale: String
    @State private var confirming: PurchaseOption?
    private var zh: Bool { locale == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(PurchaseOption.ordered(zh: zh)) { option in
                row(option)
            }
            if PurchaseOption.allCases.contains(where: { store.purchaseConfiguration.checkout(option: $0, source: nil) == nil }) {
                Text(tr(locale, "付款通道开通中，先免费试用。", "Payments open soon. Try it free meanwhile."))
                    .font(Theme.caption).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func row(_ option: PurchaseOption) -> some View {
        let available = store.purchaseConfiguration.checkout(option: option, source: store.checkoutSource) != nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: option == .oneTimeAnnual ? "qrcode" : "creditcard")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.goldText).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option == .oneTimeAnnual ? tr(locale, "微信支付 / 支付宝", "WeChat Pay / Alipay")
                                                  : tr(locale, "银行卡 / Apple Pay", "Card / Apple Pay")).font(Theme.bodyStrong)
                    Text(option == .oneTimeAnnual ? tr(locale, "一次付一年 · 到期前 7 天提醒", "Pay once for a year · reminder before it ends")
                                                  : tr(locale, "每年自动续费 · 随时取消", "Renews yearly · cancel anytime"))
                        .font(Theme.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                if available {
                    Button(tr(locale, "购买", "Buy")) {
                        store.selectedPurchaseOption = option
                        withAnimation(Theme.motion) { confirming = confirming == option ? nil : option }
                    }.buttonStyle(PrimaryButtonStyle(expand: false))
                        .accessibilityIdentifier("pro-checkout-" + option.rawValue)
                }
            }
            if confirming == option {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(PurchaseTerms.lines(locale: locale, option: option), id: \.self) {
                        Text(verbatim: "· " + $0).font(Theme.caption).foregroundStyle(Theme.secondary)
                    }
                    Button(tr(locale, "同意条款，去付款", "Agree and continue to payment")) {
                        if store.purchaseConfiguration.openCheckout(option: option, termsPresented: true,
                            source: store.checkoutSource, open: { NSWorkspace.shared.open($0) }) {
                            store.checkoutReturned()
                            confirming = nil
                        }
                    }.buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .opacity(available ? 1 : 0.6)
    }
}

struct CourseSourceField: View {
    @ObservedObject var store: SnapshotStore
    let locale: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(PurchaseTerms.localized("Course source code (optional)", locale: locale),
                      text: Binding(get: { store.courseSourceCode }, set: { store.courseSourceCode = String($0.prefix(32)) }))
                .textFieldStyle(.plain).font(Theme.caption)
                .padding(.horizontal, 8).frame(height: 28)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if let source = store.courseSource {
                Text(verbatim: source.title[locale] ?? source.code).font(Theme.caption)
                Toggle(PurchaseTerms.localized("Include this source code at checkout", locale: locale), isOn: $store.includeCourseSource)
                    .font(Theme.caption)
            }
        }
    }
}

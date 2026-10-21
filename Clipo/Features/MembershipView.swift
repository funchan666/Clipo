import SwiftUI
import StoreKit

struct MembershipView: View {
    var rewardKind: AllowanceKind? = nil
    @Environment(\.locale) private var locale
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?
    @State private var attemptedPurchaseAction = false
    @State private var purchaseHelp = false
    @State private var purchaseTask: Task<Void, Never>?

    private var plans: [CommerceConfiguration.Product] { commerce.policy?.products ?? [] }
    private var selectedPlan: CommerceConfiguration.Product? {
        plans.first(where: { $0.id == selectedID }) ?? plans.first
    }
    private var purchasing: Bool { commerce.preparingPurchase || commerce.busy || purchaseTask != nil }
    private var interactionLocked: Bool { purchasing || ads.busy || ads.isPresenting }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 12) {
                    TennisArtwork(kind: .bag, height: 164)
                        .accessibilityHidden(true)
                    LocalizedText(commerce.premium ? "More court time." : "Keep your game growing.")
                        .font(.system(.largeTitle, design: .serif, weight: .medium))
                        .foregroundStyle(ClipoStyle.paper)
                    LocalizedText("Unlimited views. Unlimited downloads.")
                        .font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                }.multilineTextAlignment(.center).frame(maxWidth: .infinity)

                if commerce.premium {
                    VStack(alignment: .leading, spacing: 10) {
                        LocalizedText("Your membership is active").font(.headline)
                        if let expiration = commerce.expiration {
                            LocalizedText("Access through \(expiration.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))).")
                                .font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                } else {
                    if api.session == nil { ConnectionPanel() }
                    VStack(spacing: 12) {
                        ForEach(plans) { plan in
                            planRow(plan)
                        }
                    }
                    VStack(spacing: 12) {
                        ActionButton(title: purchaseButtonTitle) { subscribe() }
                            .disabled(interactionLocked || selectedPlan == nil)
                            .accessibilityIdentifier("membership.subscribe")
                        if purchasing {
                            Image("ClipoLoadingMark").resizable().scaledToFit()
                                .frame(width: 42, height: 6)
                                .phaseAnimator([false, true]) { content, dimmed in
                                    content.opacity(reduceMotion || scenePhase != .active ? 1 : (dimmed ? 0.3 : 1))
                                } animation: { _ in
                                    reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.6)
                                }
                                .accessibilityHidden(true)
                        }
                        LocalizedText("USD reference prices. Apple confirms your local price before payment.")
                            .font(.caption).foregroundStyle(ClipoStyle.secondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                }

                if attemptedPurchaseAction {
                    if let error = commerce.error { ErrorNote(message: error) }
                    if let message = commerce.message {
                        LocalizedText(message).font(.subheadline).foregroundStyle(ClipoStyle.accent)
                    }
                }

                if !commerce.premium, api.session != nil { rewardOption }

                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { recoveryLinks }
                        VStack(alignment: .leading, spacing: 10) { recoveryLinks }
                    }
                    LocalizedText("Auto-renewing subscription. Cancel in your Apple account at least 24 hours before renewal. Payment is charged after Apple confirmation.")
                        .font(.caption).foregroundStyle(ClipoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PolicyLinks()
                    Button("Purchase help") { purchaseHelp.toggle() }
                        .buttonStyle(CompactActionStyle())
                    if purchaseHelp {
                        LocalizedText("If a payment is waiting to be confirmed, retry without purchasing again.")
                            .font(.footnote).foregroundStyle(ClipoStyle.secondary)
                        ActionButton(title: "Retry purchase confirmation", primary: false) {
                            attemptedPurchaseAction = true
                            commerce.retryPending()
                        }.disabled(interactionLocked)
                    }
                }
            }.padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 24)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SheetHeading(title: "Plus") { dismiss() }
                .disabled(interactionLocked).padding(.bottom, 8)
                .clipoScreenBackground()
        }
        .clipoScreenBackground().foregroundStyle(.white)
        .task { await commerce.refresh() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in quota.resetIfNeeded() }
        .onDisappear { purchaseTask?.cancel(); purchaseTask = nil }
        .interactiveDismissDisabled(interactionLocked)
        .fullScreenCover(item: $ads.luckyReward) { reward in
            LuckyRewardView(message: reward.message) { ads.luckyReward = nil }
                .presentationBackground(.clear)
        }
    }

    private var purchaseButtonTitle: String {
        if commerce.loadingProducts { return "Checking with Apple…" }
        if commerce.preparingPurchase { return "Preparing your subscription…" }
        if commerce.busy { return "Confirming your purchase…" }
        return "Continue with \(selectedPlan?.label ?? "Plus")"
    }

    private func planRow(_ plan: CommerceConfiguration.Product) -> some View {
        let selected = selectedPlan?.id == plan.id
        // The card remains a USD reference; purchase() requests the current Apple product.
        let price = "US$\(plan.displayPriceUSD)"
        let foreground = selected ? ClipoStyle.ink : ClipoStyle.paper
        let secondary = selected ? ClipoStyle.paperSecondary : ClipoStyle.secondary
        return Button { selectedID = plan.id } label: {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    planName(plan, selected: selected, foreground: foreground, secondary: secondary)
                    Spacer(minLength: 0)
                    planPrice(price, plan: plan, foreground: foreground, secondary: secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    planName(plan, selected: selected, foreground: foreground, secondary: secondary)
                    planPrice(price, plan: plan, foreground: foreground, secondary: secondary)
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background { OriginalSurface(tone: selected ? .ivory : .pine) }
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(PressStyle()).disabled(interactionLocked)
            .accessibilityLabel(Text(verbatim: L10n.display("\(plan.label), \(price) per \(plan.period.rawValue)", language: AppLanguage.from(locale))))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("membership.plan.\(plan.period.rawValue)")
    }

    private func planName(_ plan: CommerceConfiguration.Product, selected: Bool, foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(plan.label).font(.headline).foregroundStyle(foreground)
            LocalizedText(selected ? "Selected" : (plan.period == .year ? "A full year of Plus" : "One month of Plus"))
                .font(.caption).foregroundStyle(secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func planPrice(_ price: String, plan: CommerceConfiguration.Product, foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(verbatim: price).environment(\.layoutDirection, .leftToRight).font(.title.weight(.bold)).foregroundStyle(foreground).fixedSize()
            LocalizedText("per \(plan.period.rawValue)").font(.caption).foregroundStyle(secondary)
        }
    }

    private func subscribe() {
        guard !interactionLocked, let plan = selectedPlan else { return }
        attemptedPurchaseAction = true
        purchaseTask = Task {
            await commerce.purchase(planID: plan.id)
            purchaseTask = nil
        }
    }

    private var rewardOption: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedText("Or, keep it free").font(.headline)
            ForEach(rewardKind.map { [$0] } ?? AllowanceKind.allCases) { kind in
                if quota.canRequestReward(for: kind, premium: commerce.premium) {
                    LocalizedText(quota.rewardSummary(for: kind)).font(.footnote).foregroundStyle(ClipoStyle.secondary)
                    ActionButton(title: kind == .watch ? "Get more views" : "Get more downloads",
                                 primary: false, busy: ads.busy || ads.isPresenting) {
                        Task { await ads.watch(commerce: commerce, quota: quota, kind: kind) }
                    }.disabled(purchasing || ads.isPreparingAppOpen)
                }
            }
            LocalizedText(quota.unlimited ? "Unlimited views until 05:00 UTC" : "\(quota.watchesLeft) views left today")
            LocalizedText(quota.downloadsUnlimited ? "Unlimited downloads until 05:00 UTC" : "\(quota.downloadsLeft) downloads left today")
            LocalizedText("Ad rewards unlock when the corresponding allowance runs out.")
                .font(.caption).foregroundStyle(ClipoStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = ads.error { ErrorNote(message: error) }
            if let error = quota.error { ErrorNote(message: error) }
            if let message = ads.message {
                LocalizedText(message).font(.footnote).foregroundStyle(ClipoStyle.accent)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private var recoveryLinks: some View {
        Button("Restore purchases") {
            attemptedPurchaseAction = true
            commerce.restore()
        }.disabled(interactionLocked).buttonStyle(CompactActionStyle())
        Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            .buttonStyle(CompactActionStyle())
            .disabled(interactionLocked)
    }
}

struct AccountView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    @State private var paywall = false
    private var unavailable: Bool {
        accountAccess.isBusy || commerce.busy || commerce.preparingPurchase || ads.busy || ads.isPresenting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let session = api.session {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            accountIdentity(session.userId.value)
                            Spacer(minLength: 16)
                            accountStatus
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            accountIdentity(session.userId.value)
                            accountStatus
                        }
                    }
                    membershipCard
                    allowance
                    AccountSettingsSection()
                } else { ConnectionPanel() }
                LocalizedText("Version \(api.configuration.version)")
                    .font(.caption).foregroundStyle(ClipoStyle.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 4)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 24)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.clipoScreenBackground().foregroundStyle(.white)
            .sheet(isPresented: $paywall) { MembershipView() }
    }

    private func accountIdentity(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            LocalizedText("Your practice space").font(.headline).foregroundStyle(ClipoStyle.paper)
            LocalizedText("ID · \(id)").font(.caption.monospaced()).foregroundStyle(ClipoStyle.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountStatus: some View {
        LocalizedText(commerce.premium ? "Plus active" : "Free plan")
            .font(.caption.weight(.semibold))
            .foregroundStyle(commerce.premium ? ClipoStyle.accent : ClipoStyle.secondary)
    }

    private var membershipCard: some View {
        Button { paywall = true } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    membershipCopy
                    TennisArtwork(kind: .bag, height: 126).frame(width: 132)
                }
                VStack(alignment: .leading, spacing: 12) {
                    TennisArtwork(kind: .bag, height: 100)
                    membershipCopy
                }
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(ClipoStyle.paper, in: RoundedRectangle(cornerRadius: 24))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(PressStyle()).disabled(unavailable)
            .accessibilityIdentifier("account.membership")
    }

    private var membershipCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText(commerce.premium ? "Your court pass." : "Go further with Plus.")
                .font(.title2.weight(.bold)).tracking(-0.5).foregroundStyle(ClipoStyle.ink)
            LocalizedText("Unlimited views. Unlimited downloads.")
                .font(.footnote).foregroundStyle(ClipoStyle.paperSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText(commerce.premium ? "Manage membership" : "Explore plans")
                .font(.footnote.weight(.semibold)).foregroundStyle(ClipoStyle.ink)
                .padding(.top, 8)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var allowance: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                LocalizedText("Today").font(.headline)
                Spacer()
                if !commerce.premium {
                    Button("Get more") { paywall = true }
                        .font(.footnote.weight(.semibold)).foregroundStyle(ClipoStyle.accent)
                        .frame(minHeight: 44).buttonStyle(PressStyle()).disabled(unavailable)
                        .accessibilityLabel("Get more daily views and downloads")
                }
            }
            HStack(alignment: .top, spacing: 20) {
                balance(value: commerce.premium || quota.unlimited ? "Unlimited" : "\(quota.watchesLeft)", label: "Views left")
                balance(value: commerce.premium || quota.downloadsUnlimited ? "Unlimited" : "\(quota.downloadsLeft)", label: "Downloads left")
            }
            LocalizedText(commerce.premium ? "Included with your membership" : "Daily allowance resets at 05:00 UTC")
                .font(.caption).foregroundStyle(ClipoStyle.secondary)
        }
    }

    private func balance(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(value).font(value == "Unlimited" ? .title3.weight(.bold) : .largeTitle.weight(.semibold))
                .monospacedDigit().foregroundStyle(ClipoStyle.paper)
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText(label).font(.footnote).foregroundStyle(ClipoStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LuckyRewardView: View {
    let message: String
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    TennisArtwork(kind: .bag, height: 140)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                        .accessibilityHidden(true)
                    LocalizedText("A little luck, on us").font(.title2.bold()).foregroundStyle(.white)
                    LocalizedText("No ad is available right now. \(message)")
                        .font(.body).foregroundStyle(ClipoStyle.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: "Keep exploring", action: dismiss)
                }.padding(26).frame(maxWidth: 420)
                    .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 28))
                    .padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(Color.black.opacity(0.68).ignoresSafeArea())
            .accessibilityAddTraits(.isModal).interactiveDismissDisabled()
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { appeared = true } }
    }
}

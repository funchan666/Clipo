import SwiftUI
import StoreKit

struct MembershipView: View {
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
                    ClipoIllustration(name: "ClipoArtPlus", height: 136)
                        .accessibilityHidden(true)
                    Text(commerce.premium ? "More is yours." : "More to love.")
                        .font(.largeTitle.weight(.bold)).tracking(-1)
                        .foregroundStyle(ClipoStyle.paper)
                    Text("Unlimited views. Unlimited saves.")
                        .font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                }.multilineTextAlignment(.center).frame(maxWidth: .infinity)

                if commerce.premium {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your membership is active").font(.headline)
                        if let expiration = commerce.expiration {
                            Text("Access through \(expiration.formatted(date: .abbreviated, time: .omitted)).")
                                .font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                } else {
                    if api.session == nil { SignInPanel() }
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
                        Text("USD reference prices. Apple confirms your local price before payment.")
                            .font(.caption).foregroundStyle(ClipoStyle.secondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                }

                if attemptedPurchaseAction {
                    if let error = commerce.error { ErrorNote(message: error) }
                    if let message = commerce.message {
                        Text(message).font(.subheadline).foregroundStyle(ClipoStyle.accent)
                    }
                }

                if !commerce.premium, api.session != nil { rewardOption }

                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 24) { recoveryLinks }
                        VStack(alignment: .leading, spacing: 0) { recoveryLinks }
                    }
                    Text("Auto-renewing subscription. Cancel in your Apple account at least 24 hours before renewal. Payment is charged after Apple confirmation.")
                        .font(.caption).foregroundStyle(ClipoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PolicyLinks()
                    Button("Purchase help") { purchaseHelp.toggle() }
                        .font(.caption).foregroundStyle(ClipoStyle.secondary)
                        .frame(minHeight: 44).buttonStyle(PressStyle())
                    if purchaseHelp {
                        Text("If a payment is waiting to be confirmed, retry without purchasing again.")
                            .font(.footnote).foregroundStyle(ClipoStyle.secondary)
                        Button("Retry purchase confirmation") {
                            attemptedPurchaseAction = true
                            commerce.retryPending()
                        }.frame(minHeight: 44).buttonStyle(PressStyle())
                            .disabled(interactionLocked)
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
            .background(selected ? ClipoStyle.paper : ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(PressStyle()).disabled(interactionLocked)
            .accessibilityLabel("\(plan.label), \(price) per \(plan.period.rawValue)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("membership.plan.\(plan.period.rawValue)")
    }

    private func planName(_ plan: CommerceConfiguration.Product, selected: Bool, foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.label).font(.headline).foregroundStyle(foreground)
            Text(selected ? "Selected" : (plan.period == .year ? "A full year of Plus" : "One month of Plus"))
                .font(.caption).foregroundStyle(secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func planPrice(_ price: String, plan: CommerceConfiguration.Product, foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(price).font(.title.weight(.bold)).foregroundStyle(foreground).fixedSize()
            Text("per \(plan.period.rawValue)").font(.caption).foregroundStyle(secondary)
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
            Text("Or, keep it free").font(.headline)
            Text(quota.rewardSummary).font(.footnote).foregroundStyle(ClipoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ActionButton(title: "Watch an ad", primary: false, busy: ads.busy || ads.isPresenting) {
                Task { await ads.watch(commerce: commerce, quota: quota) }
            }.disabled(purchasing)
            Text(quota.unlimited ? "Unlimited views until 5 AM" : "\(quota.watchesLeft) views · \(quota.favoritesLeft) saves left today")
                .font(.caption).foregroundStyle(ClipoStyle.secondary)
            if let error = ads.error { ErrorNote(message: error) }
            if let error = quota.error { ErrorNote(message: error) }
            if let message = ads.message {
                Text(message).font(.footnote).foregroundStyle(ClipoStyle.accent)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private var recoveryLinks: some View {
        Button("Restore purchases") {
            attemptedPurchaseAction = true
            commerce.restore()
        }.disabled(interactionLocked).frame(minHeight: 44)
            .buttonStyle(PressStyle()).font(.footnote.weight(.medium))
        Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            .font(.footnote.weight(.medium)).frame(minHeight: 44)
            .disabled(interactionLocked)
    }
}

struct AccountView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    var signedOut: () -> Void
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
                    AccountSettingsSection(signedOut: signedOut)
                } else { SignInPanel() }
                Text("Version \(api.configuration.version)")
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
            Text("Guest account").font(.headline).foregroundStyle(ClipoStyle.paper)
            Text("ID · \(id)").font(.caption.monospaced()).foregroundStyle(ClipoStyle.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountStatus: some View {
        Text(commerce.premium ? "Plus active" : "Free plan")
            .font(.caption.weight(.semibold))
            .foregroundStyle(commerce.premium ? ClipoStyle.accent : ClipoStyle.secondary)
    }

    private var membershipCard: some View {
        Button { paywall = true } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    membershipCopy
                    Image("ClipoArtPlus").resizable().scaledToFit()
                        .frame(width: 132, height: 126).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Image("ClipoArtPlus").resizable().scaledToFit()
                        .frame(height: 100).accessibilityHidden(true)
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
            Text(commerce.premium ? "Your Plus." : "Make it Plus.")
                .font(.title2.weight(.bold)).tracking(-0.5).foregroundStyle(ClipoStyle.ink)
            Text("Unlimited views & saves.")
                .font(.footnote).foregroundStyle(ClipoStyle.paperSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(commerce.premium ? "Manage membership" : "Explore plans")
                .font(.footnote.weight(.semibold)).foregroundStyle(ClipoStyle.ink)
                .padding(.top, 8)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var allowance: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.headline)
                Spacer()
                if !commerce.premium {
                    Button("Get more") { paywall = true }
                        .font(.footnote.weight(.semibold)).foregroundStyle(ClipoStyle.accent)
                        .frame(minHeight: 44).buttonStyle(PressStyle()).disabled(unavailable)
                        .accessibilityLabel("Get more daily views and saves")
                }
            }
            HStack(alignment: .top, spacing: 20) {
                balance(value: commerce.premium || quota.unlimited ? "Unlimited" : "\(quota.watchesLeft)", label: "Views left")
                balance(value: commerce.premium ? "Unlimited" : "\(quota.favoritesLeft)", label: "Saves left")
            }
            Text(commerce.premium ? "Included with your membership" : "Daily allowance resets at 5 AM")
                .font(.caption).foregroundStyle(ClipoStyle.secondary)
        }
    }

    private func balance(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(value == "Unlimited" ? .title3.weight(.bold) : .largeTitle.weight(.semibold))
                .monospacedDigit().foregroundStyle(ClipoStyle.paper)
                .fixedSize(horizontal: false, vertical: true)
            Text(label).font(.footnote).foregroundStyle(ClipoStyle.secondary)
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
                    ClipoIllustration(name: "ClipoArtPlus", height: 140)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                        .accessibilityHidden(true)
                    Text("A little luck, on us").font(.title2.bold()).foregroundStyle(.white)
                    Text("No ad is available right now. \(message)")
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

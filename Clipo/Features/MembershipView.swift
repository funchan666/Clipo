import SwiftUI
import StoreKit

struct MembershipView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SheetHeading(title: "Membership") { dismiss() }.padding(.horizontal, -20).padding(.top, -12)
                VStack(alignment: .leading, spacing: 24) {
                    Text("CLIPO PLUS").font(.caption.weight(.bold)).tracking(1.4)
                        .foregroundStyle(ClipoStyle.paperSecondary)
                    ClipoIllustration(name: "ClipoArtPlus", height: 168)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(commerce.premium ? "You’re on Plus." : "Stay in the flow.")
                            .font(.largeTitle.weight(.bold)).tracking(-1.2).foregroundStyle(ClipoStyle.ink)
                        Text("Unlimited views. Unlimited saves.")
                            .font(.subheadline).foregroundStyle(ClipoStyle.paperSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(ClipoStyle.paper, in: RoundedRectangle(cornerRadius: 26))
                if commerce.premium {
                    MessagePanel(title: "Membership is active", message: "Unlimited viewing and saves, without rewarded-ad interruptions.")
                    if let expiration = commerce.expiration {
                        Text("Current access through \(expiration.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                    }
                } else {
                    SectionLabel(title: "Choose your plan", detail: "Billed by Apple")
                    if api.session == nil { SignInPanel() }
                    if commerce.products.isEmpty {
                        MessagePanel(title: "Plans are loading", message: "Prices and availability come directly from the App Store.", actionTitle: "Reload plans") { commerce.loadProducts() }
                    } else {
                        ForEach(commerce.products, id: \.productIdentifier) { product in
                            Button { Task { await commerce.buy(product) } } label: {
                                VStack(alignment: .leading, spacing: 18) {
                                    ViewThatFits(in: .horizontal) {
                                        HStack(alignment: .firstTextBaseline, spacing: 20) {
                                            planTitle(product)
                                            Spacer(minLength: 0)
                                            Text(commerce.price(product)).font(.title2.weight(.bold))
                                                .foregroundStyle(ClipoStyle.accent).fixedSize()
                                        }
                                        VStack(alignment: .leading, spacing: 12) {
                                            planTitle(product)
                                            Text(commerce.price(product)).font(.title2.weight(.bold))
                                                .foregroundStyle(ClipoStyle.accent)
                                        }
                                    }
                                    Text("Subscribe with Apple").font(.caption.weight(.medium))
                                        .foregroundStyle(ClipoStyle.secondary)
                                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(ClipoStyle.line, lineWidth: 1) }

                            }.buttonStyle(PressStyle()).disabled(commerce.busy || !commerce.purchasesAllowed)
                        }
                    }
                    if commerce.busy { Text("Waiting for Apple or confirming your purchase…").font(.subheadline).foregroundStyle(ClipoStyle.accent) }
                    if api.session != nil {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("A little more, for free").font(.headline)
                                Spacer(minLength: 8)
                                Glyph(symbol: .play, size: 19)
                            }
                            Text(quota.rewardSummary).font(.subheadline).foregroundStyle(ClipoStyle.secondary).lineSpacing(3)
                            ActionButton(title: "Watch ad for more views", primary: false, busy: ads.busy || ads.isPresenting) {
                                Task { await ads.watch(commerce: commerce, quota: quota) }
                            }
                            Text(quota.unlimited ? "Unlimited views until 5 AM" : "\(quota.watchesLeft) views · \(quota.favoritesLeft) saves left today")
                                .font(.footnote).foregroundStyle(ClipoStyle.secondary)
                        }.padding(22).background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                    }
                }
                if let error = commerce.error { ErrorNote(message: error) }
                if let error = ads.error { ErrorNote(message: error) }
                if let error = quota.error { ErrorNote(message: error) }
                if let message = commerce.message { Text(message).font(.subheadline).foregroundStyle(ClipoStyle.accent) }
                if let message = ads.message { Text(message).font(.subheadline).foregroundStyle(ClipoStyle.accent) }
                VStack(alignment: .leading, spacing: 0) {
                    Button(commerce.busy ? "Please wait…" : "Restore purchases") { commerce.restore() }
                        .disabled(commerce.busy).frame(minHeight: 44)
                    Button("Retry purchase confirmation") { commerce.retryPending() }.frame(minHeight: 44)
                }.font(.subheadline.weight(.medium)).foregroundStyle(ClipoStyle.secondary).buttonStyle(PressStyle())
                Link("Manage Apple subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    .font(.subheadline).foregroundStyle(ClipoStyle.accent)
                Text("Subscriptions renew automatically unless cancelled in your Apple account at least 24 hours before the current period ends. Payment is charged to your Apple account after confirmation. Local video editing does not require a subscription.")
                    .font(.footnote).foregroundStyle(ClipoStyle.secondary).fixedSize(horizontal: false, vertical: true)
                PolicyLinks()
            }.clipoPage()
        }.background(ClipoStyle.background).foregroundStyle(.white)
            .task { commerce.loadProducts(); await commerce.refresh() }
            .interactiveDismissDisabled(commerce.busy || ads.busy || ads.isPresenting)
    }
    private func planTitle(_ product: SKProduct) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(product.localizedTitle).font(.headline).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(commerce.period(product)).font(.subheadline).foregroundStyle(ClipoStyle.secondary)
        }
    }

}

struct AccountView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    var signedOut: () -> Void
    @State private var paywall = false
    @State private var confirmSignOut = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Your space", title: "Me")
                if let session = api.session {
                    HStack(alignment: .top, spacing: 16) {
                        Image("ClipoLaunchMark").resizable().scaledToFit().frame(width: 52, height: 52)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Guest account").font(.title3.bold())
                            Text("ID · \(session.userId.value)").font(.caption.monospaced()).foregroundStyle(ClipoStyle.secondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Your library stays on this device.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { paywall = true } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(commerce.premium ? "YOUR MEMBERSHIP" : "MAKE ROOM FOR MORE")
                                .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(ClipoStyle.paperSecondary)
                            ClipoIllustration(name: "ClipoArtPlus", height: 120)
                            Text("Clipo Plus").font(.title.weight(.bold)).foregroundStyle(ClipoStyle.ink)
                            Text(commerce.premium ? "Your membership is active." : "Unlimited views. Unlimited saves.")
                                .font(.subheadline).foregroundStyle(ClipoStyle.paperSecondary)
                            Text(commerce.premium ? "Manage membership" : "Explore plans")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(ClipoStyle.ink)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .background(ClipoStyle.paper, in: RoundedRectangle(cornerRadius: 26))
                    }.buttonStyle(PressStyle())
                    MessagePanel(title: "Today’s allowance", message: commerce.premium || quota.unlimited ? "Unlimited viewing. Daily rewards reset at 5 AM." : "\(quota.watchesLeft) views and \(quota.favoritesLeft) saves remaining. Daily rewards reset at 5 AM.")
                    if !commerce.premium {
                        ActionButton(title: "View daily rewards", primary: false) { paywall = true }
                    }
                    SectionLabel(title: "Account & privacy")
                    if confirmSignOut {
                        MessagePanel(title: "Sign out of this installation?", message: "Local files and saved clips will remain on this device. This does not delete your server account.")
                        ActionButton(title: "Sign out") {
                            do { try api.signOut(); signedOut() } catch { self.error = error.localizedDescription }
                        }
                        ActionButton(title: "Stay signed in", primary: false) { confirmSignOut = false }
                    } else {
                        ActionButton(title: "Sign out", primary: false) { confirmSignOut = true }
                            .disabled(commerce.busy || ads.isPresenting)
                    }
                } else { SignInPanel() }
                if ads.privacyOptionsRequired {
                    ActionButton(title: "Advertising privacy choices", primary: false) { Task { await ads.privacyOptions() } }
                }
                PolicyLinks()
                if let error { ErrorNote(message: error) }
                Text("Clipo \(api.configuration.version)").font(.footnote).foregroundStyle(ClipoStyle.secondary)
            }.clipoPage()
        }.background(ClipoStyle.background).foregroundStyle(.white)
            .sheet(isPresented: $paywall) { MembershipView() }
    }
}

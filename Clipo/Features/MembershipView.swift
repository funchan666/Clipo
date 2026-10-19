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
                SheetHeading(title: "Clipo Plus") { dismiss() }
                PageHeading(eyebrow: "Keep your flow", title: commerce.premium ? "You’re on Plus." : "More watching.\nLess waiting.")
                if commerce.premium {
                    MessagePanel(title: "Membership is active", message: "Unlimited viewing and saves, without rewarded-ad interruptions.")
                    if let expiration = commerce.expiration {
                        Text("Current access through \(expiration.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                    }
                } else {
                    Text("Unlimited viewing and saves. Keep your focus on the next clip.").foregroundStyle(ClipoStyle.secondary)
                    if api.session == nil { SignInPanel() }
                    if commerce.products.isEmpty {
                        MessagePanel(title: "Plans are loading", message: "Prices and availability come directly from the App Store.", actionTitle: "Reload plans") { commerce.loadProducts() }
                    } else {
                        ForEach(commerce.products, id: \.productIdentifier) { product in
                            Button { Task { await commerce.buy(product) } } label: {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(product.localizedTitle).font(.title3.bold())
                                        Text(commerce.period(product)).font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                                    }
                                    Spacer()
                                    Text(commerce.price(product)).font(.title2.bold()).foregroundStyle(ClipoStyle.accent)
                                }.padding(22).frame(minHeight: 88).background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                            }.buttonStyle(PressStyle()).disabled(commerce.busy || !commerce.purchasesAllowed)
                        }
                    }
                    if commerce.busy { Text("Waiting for Apple or confirming your purchase…").font(.subheadline).foregroundStyle(ClipoStyle.accent) }
                    if api.session != nil {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Or, take an ad break.").font(.title3.bold())
                            Text(quota.rewardSummary).foregroundStyle(ClipoStyle.secondary)
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
                ActionButton(title: "Restore purchases", primary: false, busy: commerce.busy) { commerce.restore() }
                ActionButton(title: "Retry purchase confirmation", primary: false) { commerce.retryPending() }
                Link("Manage Apple subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    .font(.subheadline).foregroundStyle(ClipoStyle.accent)
                Text("Subscriptions renew automatically unless cancelled in your Apple account at least 24 hours before the current period ends. Payment is charged to your Apple account after confirmation. Local video editing does not require a subscription.")
                    .font(.footnote).foregroundStyle(ClipoStyle.secondary).fixedSize(horizontal: false, vertical: true)
                PolicyLinks()
            }.padding(22)
        }.background(ClipoStyle.background).foregroundStyle(.white)
            .task { commerce.loadProducts(); await commerce.refresh() }
            .interactiveDismissDisabled(commerce.busy || ads.busy || ads.isPresenting)
    }
}

struct AccountView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.dismiss) private var dismiss
    var signedOut: () -> Void
    @State private var paywall = false
    @State private var confirmSignOut = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SheetHeading(title: "Your space") { dismiss() }
                PageHeading(eyebrow: "Clipo", title: "Made for your flow.")
                if let session = api.session {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Guest account").font(.title3.bold())
                        Text("ID · \(session.userId.value)").font(.caption.monospaced()).foregroundStyle(ClipoStyle.secondary).textSelection(.enabled)
                        Text("Your library stays on this device.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
                    }
                    ActionButton(title: commerce.premium ? "Manage Clipo Plus" : "Discover Clipo Plus") { paywall = true }
                    MessagePanel(title: "Today’s allowance", message: commerce.premium || quota.unlimited ? "Unlimited viewing. Daily rewards reset at 5 AM." : "\(quota.watchesLeft) views and \(quota.favoritesLeft) saves remaining. Daily rewards reset at 5 AM.")
                    if confirmSignOut {
                        MessagePanel(title: "Sign out of this installation?", message: "Local files and saved clips will remain on this device. This does not delete your server account.")
                        ActionButton(title: "Sign out") {
                            do { try api.signOut(); signedOut(); dismiss() } catch { self.error = error.localizedDescription }
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
            }.padding(22)
        }.background(ClipoStyle.background).foregroundStyle(.white)
            .sheet(isPresented: $paywall) { MembershipView() }
    }
}

import SwiftUI
import WebKit

@MainActor
final class AccountAccessFlow: ObservableObject {
    @Published private(set) var busyMessage: String?
    var isBusy: Bool { busyMessage != nil }

    func perform(_ message: String, operation: () async throws -> Void) async throws {
        guard !isBusy else { throw CancellationError() }
        busyMessage = message
        defer { busyMessage = nil }
        await Task.yield()
        try await operation()
    }
}

struct AccountLoadingIndicator: View {
    let title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 20) {
            Image("ClipoLoadingMark").resizable().scaledToFill()
                .frame(width: 48, height: 6).clipped()
                .phaseAnimator([false, true]) { content, dimmed in
                    content.opacity(reduceMotion || scenePhase != .active ? 1 : (dimmed ? 0.3 : 1))
                } animation: { _ in
                    reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.6)
                }
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
        }.padding(28).frame(maxWidth: 280)
            .foregroundStyle(.white)
            .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .combine)
    }
}

struct AccountBusyModifier: ViewModifier {
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    func body(content: Content) -> some View {
        content.allowsHitTesting(!accountAccess.isBusy)
            .accessibilityHidden(accountAccess.isBusy)
            .overlay {
                if let message = accountAccess.busyMessage {
                    ZStack {
                        Color.black.opacity(0.58).ignoresSafeArea()
                        AccountLoadingIndicator(title: message).padding(24)
                    }.accessibilityAddTraits(.isModal)
                }
            }
    }
}

// Native text/layout over the app's existing surfaces; no rendered text artwork.
struct AccountDecisionDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    var showsPolicies = false
    var destructive = false
    var cancel: (() -> Void)? = nil
    let confirm: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(title).font(.title2.weight(.bold)).foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                    Text(message).font(.body).foregroundStyle(ClipoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsPolicies { PolicyLinks() }
                    VStack(spacing: 10) {
                        Button(action: confirm) {
                            Text(confirmTitle).font(.body.weight(.semibold))
                                .multilineTextAlignment(.center).padding(16)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .foregroundStyle(ClipoStyle.ink)
                                .background(destructive ? ClipoStyle.danger : ClipoStyle.accent, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(PressStyle())
                        if let cancel { ActionButton(title: "Cancel", primary: false, action: cancel) }
                    }
                }.padding(26).frame(maxWidth: 420)
                    .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 28))
                    .padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(Color.black.opacity(0.68).ignoresSafeArea())
            .accessibilityAddTraits(.isModal)
            .interactiveDismissDisabled()
            .onAppear { titleFocused = true }
    }
}

struct PolicyDocument: Identifiable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }
}

struct PolicyLinks: View {
    @EnvironmentObject private var api: APIClient
    @State private var document: PolicyDocument?
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { links }
            VStack(alignment: .leading, spacing: 2) { links }
        }.font(.footnote.weight(.medium)).foregroundStyle(ClipoStyle.accent)
            .buttonStyle(PressStyle())
            .sheet(item: $document) { PolicyBrowser(document: $0) }
    }
    @ViewBuilder private var links: some View {
        if let url = api.configuration.termsURL {
            Button("Terms of Use") { document = PolicyDocument(title: "Terms of Use", url: url) }
                .frame(minHeight: 44)
        }
        if let url = api.configuration.privacyURL {
            Button("Privacy Policy") { document = PolicyDocument(title: "Privacy Policy", url: url) }
                .frame(minHeight: 44)
        }
    }
}

@MainActor
final class PolicyBrowserState: ObservableObject {
    @Published var loading = true
    @Published var error: String?
    @Published var requestID = 0
    func retry() { error = nil; loading = true; requestID += 1 }
}

struct PolicyBrowser: View {
    let document: PolicyDocument
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = PolicyBrowserState()
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: document.title) { dismiss() }
            ZStack {
                PolicyWebView(url: document.url, state: state)
                    .accessibilityHidden(state.loading || state.error != nil)
                if let error = state.error {
                    ClipoStyle.background
                    ScrollView {
                        MessagePanel(title: "Couldn’t open this page", message: error,
                                     actionTitle: "Try again", action: { state.retry() }).padding(24)
                    }
                } else if state.loading {
                    ClipoStyle.background
                    AccountLoadingIndicator(title: "Opening document…").padding(24)
                }
            }
        }.clipoScreenBackground().foregroundStyle(.white)
    }
}

struct PolicyWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: PolicyBrowserState
    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.requestID != state.requestID else { return }
        context.coordinator.requestID = state.requestID
        view.load(URLRequest(url: url, timeoutInterval: 30))
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.navigationDelegate = nil
        view.stopLoading()
    }
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: PolicyBrowserState
        var requestID: Int?
        init(state: PolicyBrowserState) { self.state = state }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.loading = true
            state.error = nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { state.loading = false }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            state.loading = false
            state.error = "The document was interrupted. Please try again."
        }
        private func fail(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            state.loading = false
            state.error = "Check your connection and try again."
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "mailto", navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else if url.scheme == "https" || url.absoluteString == "about:blank" {
                if navigationAction.targetFrame == nil {
                    webView.load(navigationAction.request)
                    decisionHandler(.cancel)
                } else { decisionHandler(.allow) }
            } else { decisionHandler(.cancel) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame,
               let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
                state.loading = false
                state.error = "This document is temporarily unavailable. Please try again."
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}

struct AccountSettingsSection: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    @State private var document: PolicyDocument?
    private var unavailable: Bool { accountAccess.isBusy || commerce.busy || commerce.preparingPurchase || ads.busy || ads.isPreparingAppOpen || ads.isPresenting }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy & subscriptions").font(.headline)
                VStack(spacing: 0) {
                    if let url = api.configuration.privacyURL {
                        Button { document = PolicyDocument(title: "Privacy Policy", url: url) } label: {
                            AccountMenuRow(title: "Privacy Policy")
                        }
                        rowDivider
                    }
                    if let url = api.configuration.termsURL {
                        Button { document = PolicyDocument(title: "Terms of Use", url: url) } label: {
                            AccountMenuRow(title: "Terms of Use")
                        }
                        rowDivider
                    }
                    Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                        AccountMenuRow(title: "Manage subscription")
                    }
                    if ads.privacyOptionsRequired {
                        rowDivider
                        Button { Task { await ads.privacyOptions() } } label: {
                            AccountMenuRow(title: "Advertising privacy")
                        }
                    }
                }.background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                    .buttonStyle(PressStyle()).disabled(unavailable)
            }
            if let error = ads.error { ErrorNote(message: error) }
        }
            .sheet(item: $document) { PolicyBrowser(document: $0) }
    }

    private var rowDivider: some View {
        Divider().overlay(ClipoStyle.line).padding(.horizontal, 20)
    }

}

// Plain native rows with the original raster navigation glyph.
private struct AccountMenuRow: View {
    let title: String
    var detail: String? = nil
    var destructive = false
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                    .foregroundStyle(destructive ? ClipoStyle.danger : ClipoStyle.paper)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(ClipoStyle.secondary)
                }
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Glyph(symbol: .back, size: 12, tint: ClipoStyle.secondary)
                .rotationEffect(.degrees(180)).frame(width: 20, height: 24)
                .allowsHitTesting(false)
        }.padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(.interaction, Rectangle())
    }
}

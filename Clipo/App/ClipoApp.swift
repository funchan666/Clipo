import SwiftUI

@main
struct ClipoApp: App {
    @StateObject private var api: APIClient
    @StateObject private var library: LibraryStore
    @StateObject private var quota: QuotaStore
    @StateObject private var commerce: CommerceStore
    @StateObject private var ads: RewardedAds
    @StateObject private var accountAccess = AccountAccessFlow()
    init() {
        let api = APIClient()
        let quota = QuotaStore()
        _api = StateObject(wrappedValue: api)
        _library = StateObject(wrappedValue: LibraryStore())
        _quota = StateObject(wrappedValue: quota)
        _commerce = StateObject(wrappedValue: CommerceStore(api: api, quota: quota))
        _ads = StateObject(wrappedValue: RewardedAds())
    }
    var body: some Scene {
        WindowGroup {
            ClipoStartupHost().environmentObject(api).environmentObject(library)
                .environmentObject(quota).environmentObject(commerce).environmentObject(ads)
                .environmentObject(accountAccess)
                .preferredColorScheme(.dark).tint(ClipoStyle.accent)
        }
    }
}

// Keeps the original splash visible during the bounded cold-start ad opportunity.
// Guest authentication prepares configuration; entering the app remains a separate welcome action.
struct ClipoStartupHost: View {
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finished = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            if finished {
                ClipoRootView().transition(.opacity)
            } else {
                ClipoStartupView().transition(.opacity)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !finished else { return }
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 750))
                try Task.checkCancellation()
                ads.beginStartup(commerce: commerce, accountAccess: accountAccess)
            } catch { /* Leaving the foreground cancels this transition. */ }
        }
        .onReceive(ads.$startupFinished) { complete in
            if complete { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { finished = true } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { ads.didEnterBackground() }
            if phase == .active, finished {
                ads.didBecomeActive(commerce: commerce, accountAccess: accountAccess)
            }
        }
    }
}

struct ClipoStartupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Image("ClipoLaunchMark")
            .resizable().scaledToFit().frame(width: 108, height: 108)
            .overlay(alignment: .bottom) {
                Image("ClipoLoadingMark")
                    .resizable().scaledToFill().frame(width: 40, height: 5).clipped()
                    .phaseAnimator([false, true]) { content, dimmed in
                        content.opacity(reduceMotion || scenePhase != .active ? 1 : (dimmed ? 0.35 : 1))
                    } animation: { _ in
                        reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.6)
                    }
                    .offset(y: 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .all)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Clipo is starting")
            .background(Color("LaunchBackground").ignoresSafeArea())
    }
}

enum ClipoTab: Int, CaseIterable {
    case home, discover, tools, library, me
    var name: String { ["Home", "Discover", "Tools", "Library", "Me"][rawValue] }
    var artwork: String { ["TabHome", "TabDiscover", "TabTools", "TabLibrary", "TabMe"][rawValue] }
}

struct ClipoTabBar: View {
    let selection: ClipoTab
    var select: (ClipoTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ClipoTab.allCases, id: \.rawValue) { item in
                Button { select(item) } label: {
                    ZStack {
                        // Invisible layout surface; all visible tab artwork is in the PNG.
                        Color.clear
                        Image(item.artwork + (selection == item ? "Selected" : "Normal"))
                            .renderingMode(.original).resizable().interpolation(.high).scaledToFit()
                            .frame(maxWidth: 64, maxHeight: 64)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity).frame(height: 68)
                    // Hit-test geometry only (not drawn): include transparent image margins.
                    .contentShape(.interaction, Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
                .accessibilityIdentifier("tab.\(item.name.lowercased())")
            }
        }
        .frame(maxWidth: 480).padding(.horizontal, 16)
        .padding(.top, 6).padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .clipoScreenBackground()
    }
}

struct ClipoRootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: ClipoTab = .home
    @State private var editing: LocalMovie?
    var body: some View {
        ZStack {
            ClipoStyle.background.ignoresSafeArea()
            if api.hasEnteredApp, api.session != nil {
                Group {
                    switch tab {
                    case .home: HomeView(openAccount: { tab = .me }, discover: { tab = .discover }, openTools: { tab = .tools })
                    case .discover: DiscoverView()
                    case .tools: ToolsView()
                    case .library: LibraryView { movie in editing = movie }
                    case .me: AccountView { editing = nil; tab = .home }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ClipoTabBar(selection: tab) { item in
                        tab = item
                    }
                }
            } else {
                WelcomeView()
            }
        }.foregroundStyle(.white)
            .sheet(item: $editing) { EditorSheet(initialMovie: $0) }
            .task(id: api.session?.userId.value) { await commerce.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { quota.resetIfNeeded() }
            }
            .overlay(alignment: .top) {
                if let message = library.error {
                    HStack {
                        Text(message).font(.subheadline)
                        IconButton(symbol: .close, label: "Dismiss message") { library.error = nil }
                    }.padding(14).background(ClipoStyle.raised, in: RoundedRectangle(cornerRadius: 18)).padding()
                }
            }
            .modifier(AccountBusyModifier())
    }
}

struct WelcomeView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 40

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    Image("ClipoArtWelcome")
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(maxWidth: 400)
                        .frame(height: min(max(geometry.size.height * 0.46, 220), 370))
                        .accessibilityHidden(true)
                    Text("Your next\nfavorite.")
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .tracking(-1.2).lineSpacing(0)
                        .foregroundStyle(ClipoStyle.paper)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 24)
                    Spacer(minLength: 32)
                    LoginControls()
                }
                .padding(.horizontal, 28).padding(.vertical, 20)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }.clipoScreenBackground()
    }
}

struct SignInPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MessagePanel(title: "Your next clip is one tap away.", message: "Sign in to open links, browse videos and manage your membership.")
            LoginControls()
        }
    }
}

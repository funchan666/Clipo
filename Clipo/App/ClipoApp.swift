import SwiftUI

@main
struct ClipoApp: App {
    @AppStorage(AppLanguage.preferenceKey) private var languageCode = AppLanguage.en.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .en }
    @StateObject private var api: APIClient
    @StateObject private var library: LibraryStore
    @StateObject private var quota: QuotaStore
    @StateObject private var commerce: CommerceStore
    @StateObject private var offline: OfflineStore
    @StateObject private var ads: RewardedAds
    @StateObject private var accountAccess = AccountAccessFlow()
    init() {
        let api = APIClient()
        let quota = QuotaStore()
        _api = StateObject(wrappedValue: api)
        _library = StateObject(wrappedValue: LibraryStore())
        _quota = StateObject(wrappedValue: quota)
        let commerce = CommerceStore(api: api, quota: quota)
        _commerce = StateObject(wrappedValue: commerce)
        _offline = StateObject(wrappedValue: OfflineStore(api: api, quota: quota, commerce: commerce))
        _ads = StateObject(wrappedValue: RewardedAds())
    }
    var body: some Scene {
        WindowGroup {
            ClipoStartupHost().environmentObject(api).environmentObject(library)
                .environmentObject(quota).environmentObject(commerce).environmentObject(ads).environmentObject(offline)
                .environmentObject(accountAccess)
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.direction)
                .preferredColorScheme(.dark).tint(ClipoStyle.accent)
        }
    }
}

// Keeps the original splash visible during the bounded cold-start ad opportunity.
// Guest authentication prepares configuration and opens the app directly.
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
                            .frame(maxWidth: 56, maxHeight: 56)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity).frame(height: 60)
                    // Hit-test geometry only (not drawn): include transparent image margins.
                    .contentShape(.interaction, Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(LocalizedStringKey(item.name))
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
    @EnvironmentObject private var offline: OfflineStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: ClipoTab = .home
    @State private var editing: PracticeRecording?
    var body: some View {
        ZStack {
            ClipoStyle.background.ignoresSafeArea()
            if api.session != nil {
                Group {
                    switch tab {
                    case .home: HomeView(openAccount: { tab = .me }, discover: { tab = .discover }, openTools: { tab = .tools })
                    case .discover: DiscoverView()
                    case .tools: ToolsView()
                    case .library: LibraryView { movie in editing = movie }
                    case .me: AccountView()
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ClipoTabBar(selection: tab) { item in
                        tab = item
                    }
                }
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        ConnectionPanel().padding(24)
                            .frame(minHeight: geometry.size.height)
                    }
                }
            }
        }.foregroundStyle(.white)
            .sheet(item: $editing) { EditorSheet(initialMovie: $0) }
            .task(id: api.session?.userId.value) {
                await commerce.refresh()
                await offline.resumePending()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { quota.resetIfNeeded() }
            }
            .overlay(alignment: .top) {
                if let message = library.error {
                    HStack {
                        LocalizedText(message).font(.court(.subheadline))
                        IconButton(symbol: .close, label: "Dismiss message") { library.error = nil }
                    }.padding(14).background(ClipoStyle.raised, in: RoundedRectangle(cornerRadius: 18)).padding()
                }
            }
            .modifier(AccountBusyModifier())
    }
}

// A network recovery surface, not a second login or consent gate.
struct ConnectionPanel: View {
    @EnvironmentObject private var api: APIClient
    @State private var error: String?
    @State private var connecting = false
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 24) {
            TennisArtwork(kind: .racket, height: 170)
            if let error {
                MessagePanel(title: "Let’s reconnect.", message: error)
                ActionButton(title: "Try again", busy: connecting) { attempt += 1 }
            } else {
                AccountLoadingIndicator(title: "Getting your court ready…")
            }
            PolicyLinks()
        }
        .frame(maxWidth: 440).frame(maxWidth: .infinity)
        .task(id: attempt) {
            guard api.session == nil else { return }
            connecting = true
            error = nil
            defer { connecting = false }
            do { try await api.prepareVisitor() }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

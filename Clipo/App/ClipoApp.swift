import SwiftUI

@main
struct ClipoApp: App {
    @StateObject private var api: APIClient
    @StateObject private var library: LibraryStore
    @StateObject private var quota: QuotaStore
    @StateObject private var commerce: CommerceStore
    @StateObject private var ads: RewardedAds
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
                .preferredColorScheme(.dark).tint(ClipoStyle.accent)
        }
    }
}

// This brief local transition does not sign in or wait for the network.
struct ClipoStartupHost: View {
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
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { finished = true }
            } catch { /* Leaving the foreground cancels this transition. */ }
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
        .background(ClipoStyle.background)
    }
}

struct ClipoRootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var localWorkspace = false
    @State private var tab: ClipoTab = .home
    @State private var editing: LocalMovie?
    var body: some View {
        ZStack {
            ClipoStyle.background.ignoresSafeArea()
            if api.session != nil || localWorkspace {
                Group {
                    switch tab {
                    case .home: HomeView(openAccount: { tab = .me }, discover: { tab = .discover }, openTools: { tab = .tools })
                    case .discover: DiscoverView()
                    case .tools: ToolsView()
                    case .library: LibraryView { movie in editing = movie }
                    case .me: AccountView { localWorkspace = false; editing = nil; tab = .home }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ClipoTabBar(selection: tab) { item in
                        tab = item
                    }
                }
            } else {
                WelcomeView { localWorkspace = true; tab = .tools }
            }
        }.foregroundStyle(.white)
            .sheet(item: $editing) { EditorSheet(initialMovie: $0) }
            .task(id: api.session?.userId.value) { await commerce.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { quota.resetIfNeeded(); Task { await commerce.refresh() } }
            }
            .overlay(alignment: .top) {
                if let message = library.error {
                    HStack {
                        Text(message).font(.subheadline)
                        IconButton(symbol: .close, label: "Dismiss message") { library.error = nil }
                    }.padding(14).background(ClipoStyle.raised, in: RoundedRectangle(cornerRadius: 18)).padding()
                }
            }
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var api: APIClient
    var openLocal: () -> Void
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Watch it.\nMake it yours.")
                            .font(.largeTitle.weight(.bold)).tracking(-1.2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Watch what you love. Make something of your own.")
                            .font(.body).foregroundStyle(ClipoStyle.secondary).lineSpacing(4)
                    }
                    VStack(spacing: 20) {
                        FeatureRow(symbol: .link, title: "Open a link", detail: "Go straight to a video or channel.")
                        FeatureRow(symbol: .feed, title: "Find your next favorite", detail: "A full-screen feed, one swipe at a time.")
                        FeatureRow(symbol: .edit, title: "Make the cut", detail: "Trim, reframe and export your own videos.")
                    }.padding(.vertical, 28)
                    Spacer(minLength: 24)
                    VStack(alignment: .leading, spacing: 14) {
                        if let error { ErrorNote(message: error) }
                        ActionButton(title: "One-tap sign in", busy: busy) {
                            busy = true
                            error = nil
                            Task {
                                do { try await api.signIn() } catch { self.error = error.localizedDescription }
                                busy = false
                            }
                        }
                        Text("A guest account. No password needed.")
                            .font(.caption).foregroundStyle(ClipoStyle.secondary)
                            .frame(maxWidth: .infinity)
                        Button(action: openLocal) {
                            Text("Edit a local video first").font(.subheadline.weight(.medium))
                                .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(PressStyle())
                        PolicyLinks().frame(maxWidth: .infinity)
                    }
                }
                .padding(28).frame(minHeight: geometry.size.height)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
        }.background(ClipoStyle.background)
    }
}

struct SignInPanel: View {
    @EnvironmentObject private var api: APIClient
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MessagePanel(title: "Your next clip is one tap away.", message: "Sign in to open links, browse videos and manage your membership.")
            ActionButton(title: "One-tap sign in", busy: busy) {
                busy = true
                Task { do { try await api.signIn() } catch { self.error = error.localizedDescription }; busy = false }
            }
            if let error { ErrorNote(message: error) }
        }
    }
}
struct PolicyLinks: View {
    @EnvironmentObject private var api: APIClient
    var body: some View {
        HStack(spacing: 20) {
            if let url = api.configuration.termsURL { Link("Terms", destination: url) }
            if let url = api.configuration.privacyURL { Link("Privacy", destination: url) }
        }.font(.footnote).foregroundStyle(ClipoStyle.secondary)
    }
}

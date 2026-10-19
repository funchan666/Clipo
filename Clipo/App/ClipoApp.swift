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
            ClipoRootView().environmentObject(api).environmentObject(library)
                .environmentObject(quota).environmentObject(commerce).environmentObject(ads)
                .preferredColorScheme(.dark).tint(ClipoStyle.accent)
        }
    }
}
enum ClipoTab: Int, CaseIterable {
    case home, discover, studio, library
    var name: String { ["Home", "Discover", "Studio", "Library"][rawValue] }
    var glyph: ClipoGlyph { [.home, .feed, .edit, .library][rawValue] }
}
struct ClipoRootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var localWorkspace = false
    @State private var tab: ClipoTab = .home
    @State private var settings = false
    @State private var editing: LocalMovie?
    var body: some View {
        ZStack {
            ClipoStyle.background.ignoresSafeArea()
            if api.session != nil || localWorkspace {
                Group {
                    switch tab {
                    case .home: HomeView(openSettings: { settings = true }, discover: { tab = .discover }, edit: { tab = .studio })
                    case .discover: DiscoverView()
                    case .studio: EditorWorkspace(initialMovie: editing)
                    case .library: LibraryView { movie in editing = movie; tab = .studio }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(ClipoTab.allCases, id: \.rawValue) { item in
                            Button {
                                tab = item
                                if item != .studio { editing = nil }
                            } label: {
                                VStack(spacing: 2) {
                                    Glyph(symbol: item.glyph, size: 25)
                                    Color.clear.frame(height: 3).background(tab == item ? ClipoStyle.accent : Color.clear)
                                        .frame(width: 18)
                                }.frame(maxWidth: .infinity).frame(height: 60)
                                    .background(tab == item ? ClipoStyle.raised : Color.clear, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(PressStyle()).accessibilityLabel(item.name)
                                .accessibilityAddTraits(tab == item ? .isSelected : [])
                        }
                    }.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8).background(ClipoStyle.background)
                }
            } else {
                WelcomeView { localWorkspace = true; tab = .studio }
            }
        }.foregroundStyle(.white)
            .sheet(isPresented: $settings) { AccountView { localWorkspace = false; settings = false } }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text("Clipo").font(.system(.title, design: .rounded).weight(.heavy))
                    Spacer()
                    Text("PLAY / CREATE").font(.system(.caption, design: .monospaced)).foregroundStyle(ClipoStyle.secondary)
                }
                Image("ClipoMark").resizable().scaledToFit().frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 28)).padding(.top, 36)
                Text("Find a clip.\nMake it yours.").font(.system(size: 45, weight: .bold, design: .rounded)).minimumScaleFactor(0.85)
                Text("Open a link. Get lost in the feed.\nTurn your videos into something worth keeping.")
                    .font(.title3).foregroundStyle(ClipoStyle.secondary).lineSpacing(5)
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
                    Text("A guest account, securely linked to this installation.")
                        .font(.footnote).foregroundStyle(ClipoStyle.secondary)
                    ActionButton(title: "Edit a local video", primary: false, action: openLocal)
                    PolicyLinks()
                }.padding(.top, 20)
            }.padding(28)
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

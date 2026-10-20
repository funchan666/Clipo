import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    var openAccount: () -> Void
    var discover: () -> Void
    var openTools: () -> Void
    @State private var link = ""
    @State private var password = ""
    @State private var usePassword = false
    @State private var loading = false
    @State private var error: String?
    @State private var linkFailure = ""
    @State private var showingLinkFailure = false
    @State private var channel: ChannelRoute?
    @State private var player: PlayerRoute?
    @State private var paywall = false
    @State private var channels: [LandingInfo] = []
    @State private var showingLinkGuide = false
    @FocusState private var focused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Text("YOUR DAILY PRACTICE").font(.caption2.weight(.bold))
                        .tracking(2).foregroundStyle(ClipoStyle.secondary)
                    Spacer()
                    Button(commerce.premium ? "PLUS" : "Get Plus") { paywall = true }
                        .font(.caption.weight(.semibold)).foregroundStyle(ClipoStyle.accent)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(ClipoStyle.surface, in: Capsule()).buttonStyle(PressStyle())
                    IconButton(symbol: .settings, label: "Open Me and account settings", action: openAccount)
                }
                TennisCourtBanner()
                linkComposer
                linkGuide
                if let error { ErrorNote(message: error) }
                if api.session == nil { ConnectionPanel() }
                recentLinks
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(title: "From watching to playing")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        quickAction(artwork: .lesson, title: "Watch lessons", detail: "One idea for your next session", action: discover)
                        quickAction(artwork: .racket, title: "Review practice", detail: "A closer look at your own game", action: openTools)
                    }
                }
                if !channels.isEmpty {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Lesson collections").font(.headline)
                            Text("Keep learning, one session at a time.").font(.caption).foregroundStyle(ClipoStyle.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        TennisArtwork(kind: .notebook, height: 76).frame(width: 114)
                    }
                    ForEach(Array(channels.enumerated()), id: \.offset) { _, item in
                        if let info = item.extraInfo, let title = info.channelName, let short = info.externalLinks {
                            Button { channel = ChannelRoute(link: short, title: title) } label: {
                                HStack(spacing: 14) {
                                    MediaCover(url: WebAddress.media(item.shortCover), folder: false).frame(width: 62, height: 72).clipShape(RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(title).font(.headline).lineLimit(2)
                                        if let count = info.videoFileCount { Text("\(count) videos").font(.caption).foregroundStyle(ClipoStyle.secondary) }
                                    }
                                    Spacer()
                                }
                            }.buttonStyle(PressStyle())
                        }
                    }
                }
            }.clipoPage()
        }.clipoScreenBackground().scrollDismissesKeyboard(.interactively)
            .sheet(item: $channel) { ChannelView(route: $0) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
            .fullScreenCover(isPresented: $showingLinkFailure) {
                AccountDecisionDialog(title: "Couldn’t open this link", message: linkFailure,
                                      confirmTitle: "Back to link", confirm: { showingLinkFailure = false })
                    .presentationBackground(.clear)
            }
            .sheet(isPresented: $paywall) { MembershipView() }
            .sheet(isPresented: $showingLinkGuide) { LinkGuideSheet() }
            .task(id: commerce.release?.lcList?["us"]) {
                guard let links = commerce.release?.lcList?["us"], !links.isEmpty else { return }
                do { channels = try await api.channels(links: links) }
                catch { self.error = error.localizedDescription }
            }
    }
    private var linkComposer: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Glyph(symbol: .link, size: 20)
                    .frame(width: 40, height: 40)
                    .background(ClipoStyle.ink, in: RoundedRectangle(cornerRadius: 12))
                Text("Open a lesson").font(.title3.weight(.semibold)).foregroundStyle(ClipoStyle.ink)
            }
            TextField("Lesson link or short code", text: $link, axis: .vertical)
                .lineLimit(1...3).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused).font(.body).foregroundStyle(ClipoStyle.ink)
                .tint(ClipoStyle.ink).padding(16)
                .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                .environment(\.colorScheme, .light)
                .accessibilityLabel("Lesson or collection link")
            ViewThatFits(in: .horizontal) {
                HStack {
                    pasteButton
                    Spacer(minLength: 12)
                    passwordButton
                }
                VStack(alignment: .leading, spacing: 0) { pasteButton; passwordButton }
            }
            if usePassword {
                SecureField("Access password", text: $password)
                    .font(.body).foregroundStyle(ClipoStyle.ink).tint(ClipoStyle.ink).padding(16)
                    .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                    .environment(\.colorScheme, .light).accessibilityLabel("Access password")
            }
            Button(action: resolve) {
                Text(loading ? "Opening link…" : "Open link")
                    .font(.body.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(ClipoStyle.accent)
                    .background(ClipoStyle.ink, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(PressStyle()).disabled(loading || link.nilIfBlank == nil)
            if api.session != nil {
                Text(commerce.premium || quota.unlimited ? "Unlimited viewing today" : "\(quota.watchesLeft) views left today")
                    .font(.caption).foregroundStyle(ClipoStyle.paperSecondary)
            }
        }.padding(22).background(ClipoStyle.paper, in: RoundedRectangle(cornerRadius: 26))
    }
    private var pasteButton: some View {
        Button("Paste link") {
            pasteCopiedLink()
        }.font(.subheadline.weight(.semibold)).foregroundStyle(ClipoStyle.ink)
            .frame(minHeight: 44).buttonStyle(PressStyle())
    }
    private func pasteCopiedLink() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            showLinkFailure("Copy a video link or short code first, then tap Paste link.")
            return
        }
        link = text
    }
    private var linkGuide: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Have a lesson link?").font(.subheadline.weight(.semibold))
                Text("Paste the link or code shared with you.")
                    .font(.caption).foregroundStyle(ClipoStyle.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("How to") { showingLinkGuide = true }
                .font(.subheadline.weight(.semibold)).foregroundStyle(ClipoStyle.accent)
                .frame(minWidth: 44, minHeight: 44).buttonStyle(PressStyle())
        }
    }
    @ViewBuilder private var recentLinks: some View {
        if !library.history.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Recently opened").font(.headline)
                    Spacer()
                    Button("Clear") { library.clearHistory() }
                        .font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                        .frame(minHeight: 44).buttonStyle(PressStyle())
                }
                ForEach(library.history.prefix(5)) { visit in
                    HStack {
                        Button { link = visit.link; resolve() } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(visit.title).font(.headline).lineLimit(1)
                                Text(visit.link).font(.caption).foregroundStyle(ClipoStyle.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(PressStyle()).disabled(loading)
                        IconButton(symbol: .close, label: "Remove history item") { library.removeVisit(visit) }
                    }
                }
            }
        }
    }
    private var passwordButton: some View {
        Button(usePassword ? "Hide password" : "Has a password?") { usePassword.toggle() }
            .font(.subheadline).foregroundStyle(ClipoStyle.paperSecondary)
            .frame(minHeight: 44).buttonStyle(PressStyle())
    }
    private func quickAction(artwork: TennisArtwork.Kind, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                TennisArtwork(kind: artwork, height: 116)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(detail).font(.caption).foregroundStyle(ClipoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(PressStyle())
    }
    private func resolve() {
        guard let text = link.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank, !loading else { return }
        focused = false
        guard api.session != nil else { showLinkFailure("Your connection is not ready yet. Please try again."); return }
        loading = true
        error = nil
        let accessPassword = usePassword ? password : ""
        Task {
            defer { loading = false }
            do {
                let info = try await api.resolve(text, password: accessPassword)
                if let clip = info.netDiskInfo?.clip(channel: info.extraInfo?.channelName ?? "From your link") {
                    library.record(link: text, title: clip.title)
                    player = PlayerRoute(clips: [clip], startID: clip.id)
                } else if let title = info.extraInfo?.channelName?.nilIfBlank, let external = info.extraInfo?.externalLinks?.nilIfBlank {
                    library.record(link: text, title: title)
                    channel = ChannelRoute(link: external, title: title)
                } else { throw ClipoError.service("This link did not return a playable video or channel.") }
            } catch { showLinkFailure(error.localizedDescription) }
        }
    }
    private func showLinkFailure(_ message: String) {
        linkFailure = message
        showingLinkFailure = true
    }
}

struct ChannelView: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    let route: ChannelRoute
    @State private var items: [DiskItem] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var error: String?
    @State private var child: ChannelRoute?
    @State private var player: PlayerRoute?
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: route.title) { dismiss() }
            ScrollView {
                LazyVStack(spacing: 18) {
                    TennisArtwork(kind: .notebook, height: 140)
                    if items.isEmpty, !loading, error == nil { MessagePanel(title: "Nothing here yet", message: "This channel has no available videos.") }
                    ForEach(items, id: \.stableID) { item in
                        Button { open(item) } label: {
                            HStack(spacing: 16) {
                                MediaCover(url: WebAddress.media(item.coverImage), folder: item.isFolder == true)
                                    .frame(width: 80, height: 94).clipShape(RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.name ?? "Untitled").font(.headline).lineLimit(3)
                                    Text(item.isFolder == true ? "\(item.childrenFileNum ?? 0) videos" : durationLabel(item.length ?? 0))
                                        .font(.caption.monospacedDigit()).foregroundStyle(ClipoStyle.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Glyph(symbol: item.isFolder == true ? .folder : .play, size: 20)
                            }
                        }.buttonStyle(PressStyle())
                    }
                    if let error { ErrorNote(message: error) }
                    if hasMore { ActionButton(title: error == nil ? "Load more" : "Try again", primary: false, busy: loading) { Task { await load() } } }
                }.padding(22)
            }
        }.clipoScreenBackground().foregroundStyle(.white)
            .task { if items.isEmpty { await load() } }
            .sheet(item: $child) { ChannelView(route: $0) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
    }
    private func load() async {
        guard !loading, hasMore else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let result = try await api.channelPage(link: route.link, page: page)
            var seen = Set(items.map(\.stableID))
            items += result.list.filter { $0.name?.nilIfBlank != nil && !$0.stableID.isEmpty && seen.insert($0.stableID).inserted }
            hasMore = page * 20 < result.total && !result.list.isEmpty
            page += 1
        } catch { self.error = error.localizedDescription }
    }
    private func open(_ item: DiskItem) {
        if item.isFolder == true, let link = item.landingPage?.nilIfBlank {
            child = ChannelRoute(link: link, title: item.name ?? "Folder")
        } else if let clip = item.clip(channel: route.title) {
            player = PlayerRoute(clips: items.compactMap { $0.clip(channel: route.title) }, startID: clip.id)
        } else { error = "This item does not contain a playable video." }
    }
}

struct LinkGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Open your next lesson") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    TennisArtwork(kind: .lesson, height: 150)
                    FeatureRow(symbol: .link, title: "1. Copy your shared link", detail: "Use a tennis lesson link or short code shared with you.")
                    FeatureRow(symbol: .search, title: "2. Paste it above", detail: "Tap Paste link or enter the code exactly as received. Uppercase and lowercase letters matter.")
                    FeatureRow(symbol: .play, title: "3. Open and watch", detail: "Tap Open link to watch the lesson or browse its collection. Add the access password if one was provided.")
                    Text("A link not opening? Check the code and password, or ask the sender for a new link.")
                        .font(.footnote).foregroundStyle(ClipoStyle.secondary)
                    ActionButton(title: "Got it") { dismiss() }
                }.clipoPage()
            }
        }.clipoScreenBackground().foregroundStyle(.white)
    }
}

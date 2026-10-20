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
    @State private var selectedPlatform: HomeLinkPlatform?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    ClipoIllustration(name: "ClipoArtLink", height: 64).frame(width: 96)
                    Spacer()
                    Button(commerce.premium ? "PLUS" : "Get Plus") { paywall = true }
                        .font(.caption.weight(.semibold)).foregroundStyle(ClipoStyle.accent)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(ClipoStyle.surface, in: Capsule()).buttonStyle(PressStyle())
                    IconButton(symbol: .settings, label: "Open Me and account settings", action: openAccount)
                }
                linkComposer
                platformGuide
                if let error { ErrorNote(message: error) }
                if api.session == nil { SignInPanel() }
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(title: "Watch or create")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        quickAction(artwork: "ClipoArtDiscover", title: "Discover", detail: "Swipe into something new", action: discover)
                        quickAction(artwork: "ClipoArtTools", title: "Tools", detail: "Audio, speed and framing", action: openTools)
                    }
                }
                if !channels.isEmpty {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Channels to explore").font(.headline)
                            Text("Find a new point of view.").font(.caption).foregroundStyle(ClipoStyle.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        ClipoIllustration(name: "ClipoArtChannels", height: 76).frame(width: 114)
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
                if !library.history.isEmpty {
                    HStack {
                        Text("Recently opened").font(.headline)
                        Spacer()
                        Button("Clear") { library.clearHistory() }.font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                    }
                    ForEach(library.history.prefix(5)) { visit in
                        HStack {
                            Button { link = visit.link; resolve() } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(visit.title).font(.headline).lineLimit(1)
                                    Text(visit.link).font(.caption).foregroundStyle(ClipoStyle.secondary).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(PressStyle())
                            IconButton(symbol: .close, label: "Remove history item") { library.removeVisit(visit) }
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
            .sheet(item: $selectedPlatform) { LinkGuideSheet(platform: $0) }
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
                Text("Open a link").font(.title3.weight(.semibold)).foregroundStyle(ClipoStyle.ink)
            }
            TextField("Video link or short code", text: $link, axis: .vertical)
                .lineLimit(1...3).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused).font(.body).foregroundStyle(ClipoStyle.ink)
                .tint(ClipoStyle.ink).padding(16)
                .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                .environment(\.colorScheme, .light)
                .accessibilityLabel("Video or channel link")
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
    private var platformGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste a link from").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible()), GridItem(.flexible())]
                      : [GridItem(.adaptive(minimum: 68), spacing: 12)], spacing: 16) {
                ForEach(HomeLinkPlatform.allCases) { platform in
                    Button { selectedPlatform = platform } label: {
                        VStack(spacing: 6) {
                            HomePlatformIcon(platform: platform).frame(width: 68, height: 68)
                            Text(platform.name).font(.caption.weight(.medium)).foregroundStyle(.white)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, minHeight: 98, alignment: .top)
                            .contentShape(.interaction, Rectangle())
                    }.buttonStyle(PressStyle())
                        .accessibilityLabel("How to use a \(platform.name) link")
                }
            }.frame(maxWidth: 330).frame(maxWidth: .infinity)
            Text("Copy a video link, paste it above, and tap Open link.")
                .font(.footnote).foregroundStyle(ClipoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(18).background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 24))
    }
    private var passwordButton: some View {
        Button(usePassword ? "Hide password" : "Has a password?") { usePassword.toggle() }
            .font(.subheadline).foregroundStyle(ClipoStyle.paperSecondary)
            .frame(minHeight: 44).buttonStyle(PressStyle())
    }
    private func quickAction(artwork: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                ClipoIllustration(name: artwork, height: 100)
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
        guard api.session != nil else { showLinkFailure("Sign in to open this link."); return }
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
                    ClipoIllustration(name: "ClipoArtChannels", height: 140)
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

// Platform identifiers are static, user-requested source guidance, independent of backend recommendations.
enum HomeLinkPlatform: Int, CaseIterable, Identifiable {
    case tikTok, youTube, instagram, facebook, x, reddit
    case vimeo, dailymotion, pinterest, twitch, snapchat, bilibili
    var id: Int { rawValue }
    var name: String {
        ["TikTok", "YouTube", "Instagram", "Facebook", "X", "Reddit",
         "Vimeo", "Dailymotion", "Pinterest", "Twitch", "Snapchat", "Bilibili"][rawValue]
    }
}

struct HomePlatformIcon: View {
    let platform: HomeLinkPlatform
    var body: some View {
        GeometryReader { geometry in
            // Optical centers in the original 1086 × 1448 raster; display cropping only.
            let centerX: CGFloat = [216, 543, 873][platform.rawValue % 3]
            let centerY: CGFloat = [222, 552, 883, 1213][platform.rawValue / 3]
            Image("ClipoPlatformAtlas").resizable().interpolation(.high)
                .frame(width: geometry.size.width * 1086 / 330, height: geometry.size.height * 1448 / 330)
                .offset(x: (165 - centerX) * geometry.size.width / 330,
                        y: (165 - centerY) * geometry.size.height / 330)
                .allowsHitTesting(false)
        }.clipped().clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
    }
}

struct LinkGuideSheet: View {
    let platform: HomeLinkPlatform
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "\(platform.name) links") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HomePlatformIcon(platform: platform).frame(width: 96, height: 96)
                        .frame(maxWidth: .infinity)
                    FeatureRow(symbol: .search, title: "1. Copy the video link", detail: "Find a public video in \(platform.name), open its sharing options and copy the link.")
                    FeatureRow(symbol: .link, title: "2. Paste it here", detail: "Return to the home screen and tap Paste link. If you have a short code instead, enter it exactly as shared. Uppercase and lowercase letters matter.")
                    FeatureRow(symbol: .play, title: "3. Open your video", detail: "Tap Open link. A video opens in the player; a channel opens its videos and folders. Enter an access password if the shared content requires one.")
                    Text("Availability depends on the source. Private, expired or restricted links may not open.")
                        .font(.footnote).foregroundStyle(ClipoStyle.secondary)
                    ActionButton(title: "Got it") { dismiss() }
                }.clipoPage()
            }
        }.clipoScreenBackground().foregroundStyle(.white)
    }
}

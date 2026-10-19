import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    var openSettings: () -> Void
    var discover: () -> Void
    var edit: () -> Void
    @State private var link = ""
    @State private var password = ""
    @State private var usePassword = false
    @State private var loading = false
    @State private var error: String?
    @State private var channel: ChannelRoute?
    @State private var player: PlayerRoute?
    @State private var paywall = false
    @State private var channels: [LandingInfo] = []
    @FocusState private var focused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text("Clipo").font(.system(.title, design: .rounded).weight(.heavy))
                    Spacer()
                    Button(commerce.premium ? "PLUS" : "GET PLUS") { paywall = true }
                        .font(.system(.caption, design: .monospaced).weight(.bold)).foregroundStyle(ClipoStyle.accent)
                        .padding(12).background(ClipoStyle.surface, in: Capsule()).buttonStyle(PressStyle())
                    IconButton(symbol: .settings, label: "Account and settings", action: openSettings)
                }
                PageHeading(eyebrow: "Start with a link", title: "What’s worth\nwatching?")
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Glyph(symbol: .link, size: 22)
                        Text("VIDEO OR CHANNEL LINK").font(.system(.caption, design: .monospaced)).foregroundStyle(ClipoStyle.secondary)
                    }
                    TextField("Paste a link or short code", text: $link, axis: .vertical)
                        .lineLimit(1...3).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused).clipoField().accessibilityLabel("Video or channel link")
                    HStack {
                        Button("Paste link") {
                            if let text = UIPasteboard.general.string { link = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                        }
                        Spacer()
                        Button(usePassword ? "Hide password" : "Has a password?") { usePassword.toggle() }
                    }.font(.subheadline.weight(.medium)).foregroundStyle(ClipoStyle.accent).buttonStyle(PressStyle())
                    if usePassword { SecureField("Access password", text: $password).clipoField() }
                    ActionButton(title: "Open link", busy: loading) { resolve() }.disabled(link.nilIfBlank == nil)
                    if let error { ErrorNote(message: error) }
                    if api.session != nil {
                        Text(commerce.premium || quota.unlimited ? "Unlimited viewing today" : "\(quota.watchesLeft) views left today")
                            .font(.footnote).foregroundStyle(ClipoStyle.secondary)
                    }
                }.padding(20).background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 26))
                if api.session == nil { SignInPanel() }
                HStack(alignment: .top, spacing: 20) {
                    Button(action: discover) {
                        VStack(alignment: .leading, spacing: 12) {
                            Glyph(symbol: .feed, size: 31)
                            Text("Just watch").font(.title3.bold())
                            Text("A full-screen stream.\nOne clip at a time.").font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(action: edit) {
                        VStack(alignment: .leading, spacing: 12) {
                            Glyph(symbol: .edit, size: 31)
                            Text("Make a cut").font(.title3.bold())
                            Text("Trim, reframe and\nmake your next edit.").font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(PressStyle()).padding(.vertical, 6)
                if !channels.isEmpty {
                    Text("Channels to explore").font(.title3.bold())
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
                if let sites = commerce.release?.recommend, !sites.isEmpty {
                    Text("Explore a source").font(.title3.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(sites) { site in
                                Button(site.name) { link = site.url; focused = true }
                                    .padding(14).background(ClipoStyle.surface, in: Capsule()).buttonStyle(PressStyle())
                            }
                        }
                    }
                }
                if !library.history.isEmpty {
                    HStack {
                        Text("Recently opened").font(.title3.bold())
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
            }.padding(22).padding(.bottom, 18)
        }.scrollDismissesKeyboard(.interactively)
            .sheet(item: $channel) { ChannelView(route: $0) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
            .sheet(isPresented: $paywall) { MembershipView() }
            .task(id: commerce.release?.lcList?["us"]) {
                guard let links = commerce.release?.lcList?["us"], !links.isEmpty else { return }
                do { channels = try await api.channels(links: links) }
                catch { self.error = error.localizedDescription }
            }
    }
    private func resolve() {
        guard let text = link.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank, !loading else { return }
        guard api.session != nil else { error = "Sign in to open this link."; return }
        focused = false
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
            } catch { self.error = error.localizedDescription }
        }
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
        }.background(ClipoStyle.background).foregroundStyle(.white)
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

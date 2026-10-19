import SwiftUI

@MainActor
final class FeedStore: ObservableObject {
    @Published private(set) var clips: [Clip] = []
    @Published private(set) var loading = false
    @Published private(set) var hasMore = true
    @Published var error: String?
    private var feedID: String?
    private var cursor: String?
    private var query = ""
    private var generation = UUID()
    func load(api: APIClient, search: String? = nil) async {
        if let search {
            generation = UUID()
            clips = []; feedID = nil; cursor = nil; hasMore = true; loading = false; query = search
        }
        guard !loading, hasMore else { return }
        let current = generation
        loading = true
        error = nil
        defer { if generation == current { loading = false } }
        do {
            let response = try await api.feed(query: query, feedID: feedID, cursor: cursor)
            guard current == generation else { return }
            var seen = Set(clips.map(\.id))
            clips += response.list.compactMap(\.clip).filter { seen.insert($0.id).inserted }
            let oldCursor = cursor
            feedID = response.feedId
            cursor = response.nextCursor
            hasMore = response.hasMore && response.nextCursor?.nilIfBlank != nil && response.nextCursor != oldCursor && !response.list.isEmpty
        } catch { if current == generation { self.error = error.localizedDescription } }
    }
}
struct DiscoverView: View {
    @EnvironmentObject private var api: APIClient
    @StateObject private var feed = FeedStore()
    @State private var search = ""
    @State private var searchOpen = false
    @State private var activeID: String?
    var body: some View {
        ZStack(alignment: .top) {
            if api.session == nil {
                ScrollView { VStack(spacing: 24) { PageHeading(eyebrow: "Discover", title: "One more clip."); SignInPanel() }.padding(24) }
            } else if feed.clips.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    MessagePanel(title: feed.loading ? "Finding your next clip…" : "A fresh feed starts here.",
                                 message: feed.error ?? (feed.loading ? "Loading videos from Clipo." : "No videos are available for this search."),
                                 actionTitle: feed.loading ? nil : "Try again") { Task { await feed.load(api: api, search: search) } }
                    Spacer()
                }.padding(24)
            } else {
                GeometryReader { geometry in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(feed.clips) { clip in
                                ClipPage(clip: clip, active: activeID == clip.id && !searchOpen)
                                    .frame(width: geometry.size.width, height: geometry.size.height).id(clip.id)
                            }
                            if feed.error != nil || feed.hasMore {
                                VStack(spacing: 16) {
                                    Text(feed.error ?? "Finding more clips…").foregroundStyle(ClipoStyle.secondary)
                                    ActionButton(title: "Load more", primary: false, busy: feed.loading) { Task { await feed.load(api: api) } }
                                }.padding(28).frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }.scrollTargetLayout()
                    }.scrollTargetBehavior(.paging).scrollPosition(id: $activeID).scrollIndicators(.hidden)
                        .onChange(of: activeID) { _, id in
                            if let index = feed.clips.firstIndex(where: { $0.id == id }), index >= feed.clips.count - 3 {
                                Task { await feed.load(api: api) }
                            }
                        }
                }
            }
            if api.session != nil {
                VStack(spacing: 10) {
                    HStack {
                        Text("FOR YOU").font(.system(.subheadline, design: .monospaced).weight(.bold)).tracking(2)
                        Spacer()
                        IconButton(symbol: .search, label: "Search videos", selected: searchOpen) { searchOpen.toggle() }
                    }
                    if searchOpen {
                        HStack {
                            TextField("Search videos", text: $search).clipoField().submitLabel(.search)
                                .onSubmit { runSearch() }
                            Button("Go") { runSearch() }.buttonStyle(PressStyle()).foregroundStyle(ClipoStyle.accent)
                        }
                    }
                }.padding(.horizontal, 22).padding(.top, 8).background(Color.black.opacity(0.72))
            }
        }.background(Color.black)
            .task(id: api.session?.userId.value) {
                guard api.session != nil else { return }
                await feed.load(api: api, search: search)
                activeID = feed.clips.first?.id
            }
            .onChange(of: feed.clips) { _, clips in if activeID == nil { activeID = clips.first?.id } }
    }
    private func runSearch() {
        searchOpen = false
        activeID = nil
        Task { await feed.load(api: api, search: search); activeID = feed.clips.first?.id }
    }
}

struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    let route: PlayerRoute
    @State private var activeID: String?
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(route.clips) { clip in
                        ClipPage(clip: clip, active: activeID == clip.id)
                            .frame(width: geometry.size.width, height: geometry.size.height).id(clip.id)
                    }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.paging).scrollPosition(id: $activeID).scrollIndicators(.hidden)
        }.background(.black).overlay(alignment: .topLeading) {
            IconButton(symbol: .back, label: "Back") { dismiss() }
                .background(.black.opacity(0.5), in: Circle()).padding(16)
        }.onAppear { activeID = route.startID }.preferredColorScheme(.dark)
    }
}

struct ClipPage: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.scenePhase) private var phase
    let clip: Clip
    let active: Bool
    @StateObject private var playback = PlaybackController()
    @State private var loaded = false
    @State private var gate = false
    @State private var options = false
    @State private var editor = false
    @State private var share = false
    @State private var recorded = false
    @State private var allowed = false
    var body: some View {
        ZStack {
            Color.black
            if loaded { VideoSurface(player: playback.player).clipped() }
            if playback.isLoading || !loaded {
                MediaCover(url: clip.coverURL).opacity(0.45)
            }
            Color.clear.contentShape(Rectangle()).onTapGesture {
                if allowed { playback.toggle() } else { gate = true }
            }
            if let error = playback.error {
                MessagePanel(title: "This clip couldn’t load", message: error, actionTitle: "Retry") { activate(reload: true) }.padding(24)
            } else if !allowed, active {
                VStack(spacing: 16) {
                    Text("Keep watching").font(.title.bold())
                    ActionButton(title: "Get more views") { gate = true }
                }.padding(32).background(ClipoStyle.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 24)).padding(24)
            } else if !playback.isPlaying, !playback.isLoading {
                IconButton(symbol: .play, label: "Play video") { playback.play() }
                    .background(Color.black.opacity(0.4), in: Circle())
            }
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(clip.channel.uppercased()).font(.system(.caption, design: .monospaced).weight(.bold)).foregroundStyle(ClipoStyle.accent)
                        Text(clip.title).font(.title2.weight(.bold)).lineLimit(3)
                        Text("Swipe up for the next clip").font(.caption).foregroundStyle(.white.opacity(0.75))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 14) {
                        VStack(spacing: 0) {
                            IconButton(symbol: .bookmark, label: library.isSaved(clip) ? "Remove saved video" : "Save video", selected: library.isSaved(clip)) { save() }
                            Text(library.isSaved(clip) ? "Saved" : "Save").font(.caption2)
                        }
                        IconButton(symbol: playback.muted ? .mute : .sound, label: playback.muted ? "Unmute" : "Mute") { playback.setMuted(!playback.muted) }
                        IconButton(symbol: .settings, label: "Playback options") { playback.pause(); options = true }
                        IconButton(symbol: .link, label: "Share video link") { playback.pause(); share = true }
                    }
                }
                HStack {
                    Text(durationLabel(playback.elapsed)).font(.caption.monospacedDigit())
                    ClipoScrubber(value: Binding(get: { playback.elapsed }, set: { playback.seek($0) }), range: 0...max(1, playback.duration), label: "Playback position")
                    Text(durationLabel(playback.duration)).font(.caption.monospacedDigit())
                }.padding(.top, 18)
            }.padding(22).background(alignment: .bottom) {
                VStack { Spacer(); Color.black.opacity(0.68).frame(height: 220) }
                    .allowsHitTesting(false)
            }
            if active, playback.isLoading { Text("Loading…").font(.caption).padding(12).background(.black.opacity(0.6), in: Capsule()) }
        }.foregroundStyle(.white).clipped()
            .onAppear { if active { activate() } }
            .onChange(of: active) { _, active in if active { activate() } else { playback.release(); loaded = false } }
            .onChange(of: playback.isPlaying) { _, playing in
                if playing, !recorded {
                    recorded = quota.recordWatch(clip.id, premium: commerce.premium)
                    if !recorded { playback.pause(); allowed = false; gate = true }
                }
            }
            .onChange(of: phase) { _, state in if state != .active { playback.pause() } }
            .onChange(of: ads.isPresenting) { _, presenting in if presenting { playback.pause() } }
            .onDisappear { playback.release() }
            .sheet(isPresented: $gate, onDismiss: { if active { activate() } }) { MembershipView() }
            .sheet(isPresented: $options) {
                VStack(alignment: .leading, spacing: 24) {
                    SheetHeading(title: "Playback") { options = false }
                    Text("Speed").font(.title3.bold())
                    HStack {
                        ForEach([Float(0.5), 1, 1.5, 2], id: \.self) { speed in
                            Button("\(speed, specifier: "%g")×") { playback.setSpeed(speed) }
                                .padding(14).background(playback.speed == speed ? ClipoStyle.raised : ClipoStyle.surface, in: Capsule())
                        }
                    }.buttonStyle(PressStyle())
                    Text("Quality adapts automatically to your connection.").font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                    ActionButton(title: "Edit a local video", primary: false) { options = false; editor = true }
                    Text("Online streams stay online. Import a video you own to make an edit.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
                    Spacer()
                }.padding(22).background(ClipoStyle.background).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $editor) { EditorSheet() }
            .sheet(isPresented: $share) { ShareSheet(items: [WebAddress.media(clip.shortLink) ?? clip.playbackURL]) }
    }
    private func activate(reload: Bool = false) {
        guard active, phase == .active else { return }
        recorded = false
        allowed = quota.mayWatch(clip.id, premium: commerce.premium)
        if !allowed { playback.pause(); gate = true; return }
        if !loaded || reload { playback.load(clip.playbackURL, autoplay: true); loaded = true }
        else { playback.play() }
    }
    private func save() {
        if library.isSaved(clip) { library.toggle(clip); return }
        guard quota.consumeFavorite(premium: commerce.premium) else { playback.pause(); gate = true; return }
        library.toggle(clip)
        if !library.isSaved(clip), !commerce.premium { quota.refundFavorite() }
    }
}
struct ClipoScrubber: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22)).frame(height: 4)
                Capsule().fill(ClipoStyle.accent).frame(width: geometry.size.width * fraction, height: 4)
            }.frame(height: 44).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    value = range.lowerBound + min(1, max(0, gesture.location.x / max(1, geometry.size.width))) * (range.upperBound - range.lowerBound)
                })
        }.frame(height: 44).accessibilityElement().accessibilityLabel(label)
            .accessibilityValue(durationLabel(value)).accessibilityAdjustableAction { direction in
                value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? 1 : -1)))
            }
    }
}

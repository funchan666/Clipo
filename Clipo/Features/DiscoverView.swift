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
            try Task.checkCancellation()
            guard current == generation else { return }
            var seen = Set(clips.map(\.id))
            clips += response.list.compactMap(\.clip).filter { seen.insert($0.id).inserted }
            let oldCursor = cursor
            feedID = response.feedId
            cursor = response.nextCursor
            hasMore = response.hasMore && response.nextCursor?.nilIfBlank != nil && response.nextCursor != oldCursor && !response.list.isEmpty
        } catch is CancellationError {
            // Leaving a screen/search is not a service failure.
        } catch {
            if current == generation, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
struct DiscoverView: View {
    @EnvironmentObject private var api: APIClient
    @StateObject private var feed = FeedStore()
    @StateObject private var players = PlaybackPool()
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var searchOpen = false
    @State private var activeID: String?
    var body: some View {
        ZStack(alignment: .top) {
            if api.session == nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        TennisArtwork(kind: .lesson, height: 208)
                        Text("Connecting your lesson feed…")
                            .font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                        ConnectionPanel()
                    }.clipoPage()
                }
            } else if feed.clips.isEmpty {
                VStack(spacing: 0) {
                    feedHeader
                    ScrollView {
                        VStack(spacing: 24) {
                            TennisArtwork(kind: .lesson, height: 208)
                            MessagePanel(title: feed.loading ? "Finding your next lesson…" : "Your next session starts here.",
                                         message: feed.error ?? (feed.loading ? "Loading your lesson feed." : "No lessons are available here yet. Try another search or open a shared lesson link on Home."),
                                         actionTitle: feed.loading ? nil : "Try again") { Task { await feed.load(api: api, search: search) } }
                        }.clipoPage()
                    }
                }
            } else {
                GeometryReader { container in
                    GeometryReader { geometry in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(feed.clips) { clip in
                                    Group {
                                        if let playback = players.controllers[clip.id] {
                                            ClipPage(clip: clip, active: activeID == clip.id && !searchOpen,
                                                     controlInsets: container.safeAreaInsets, playback: playback,
                                                     didStartPlaying: { players.prepareNext(after: clip.id) })
                                        } else {
                                            MediaCover(url: clip.coverURL)
                                        }
                                    }.frame(width: geometry.size.width, height: geometry.size.height).clipped().id(clip.id)
                                }
                                if feed.error != nil || feed.hasMore {
                                    VStack(spacing: 16) {
                                        Text(feed.error ?? "Finding more clips…").foregroundStyle(ClipoStyle.secondary)
                                        ActionButton(title: "Load more", primary: false, busy: feed.loading) { Task { await feed.load(api: api) } }
                                    }.padding(28).padding(container.safeAreaInsets)
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                }
                            }.scrollTargetLayout()
                        }.scrollTargetBehavior(.paging).scrollPosition(id: $activeID, anchor: .top).scrollIndicators(.hidden)
                            .onChange(of: activeID) { _, id in
                                players.update(clips: feed.clips, selectedID: id)
                                if let index = feed.clips.firstIndex(where: { $0.id == id }), index >= feed.clips.count - 3 {
                                    Task { await feed.load(api: api) }
                                }
                            }
                    }.ignoresSafeArea(.container, edges: .all)
                }
            }
            if api.session != nil, !feed.clips.isEmpty {
                feedHeader
            }
        }.clipoScreenBackground(.black)
            .task(id: api.session?.userId.value) {
                guard api.session != nil else { return }
                await feed.load(api: api, search: search)
                guard !Task.isCancelled else { return }
                activeID = feed.clips.first?.id
            }
            .onChange(of: feed.clips) { _, clips in
                if !clips.contains(where: { $0.id == activeID }) { activeID = clips.first?.id }
                players.update(clips: clips, selectedID: activeID)
            }
            .onDisappear { players.releaseAll() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { players.suspend() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in players.trimMemory() }
    }
    private var feedHeader: some View {
        VStack(spacing: 10) {
            HStack {
                IconButton(symbol: .search, label: "Search videos", selected: searchOpen) { searchOpen.toggle() }
                Spacer()
                Button(feed.loading ? "Loading…" : "Refresh") { Task { await refreshFeed() } }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Color.black.opacity(0.4), in: Capsule())
                    .buttonStyle(PressStyle()).disabled(feed.loading)
            }
            if searchOpen {
                HStack {
                    TextField("Search videos", text: $search).clipoField().submitLabel(.search)
                        .onSubmit { runSearch() }
                    Button("Go") { runSearch() }.frame(minWidth: 44, minHeight: 44).buttonStyle(PressStyle()).foregroundStyle(ClipoStyle.accent)
                }
            }
        }.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
            .background(searchOpen ? Color.black.opacity(0.75) : Color.clear)
    }
    private func runSearch() {
        searchOpen = false
        activeID = nil
        Task { await feed.load(api: api, search: search); activeID = feed.clips.first?.id }
    }
    private func refreshFeed() async {
        players.releaseAll()
        activeID = nil
        await feed.load(api: api, search: search)
        guard !Task.isCancelled else { return }
        activeID = feed.clips.first?.id
    }
}

struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    let route: PlayerRoute
    @State private var activeID: String?
    @StateObject private var players = PlaybackPool()
    @Environment(\.scenePhase) private var scenePhase
    init(route: PlayerRoute) {
        self.route = route
        _activeID = State(initialValue: route.startID)
    }
    var body: some View {
        GeometryReader { container in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(route.clips) { clip in
                            Group {
                                if let playback = players.controllers[clip.id] {
                                    ClipPage(clip: clip, active: activeID == clip.id,
                                             controlInsets: container.safeAreaInsets, playback: playback,
                                             didStartPlaying: { players.prepareNext(after: clip.id) })
                                } else {
                                    MediaCover(url: clip.coverURL)
                                }
                            }.containerRelativeFrame([.horizontal, .vertical])
                                .clipped().id(clip.id)
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $activeID, anchor: .top)
                .scrollIndicators(.hidden)
                .task { proxy.scrollTo(route.startID, anchor: .top) }
            }.ignoresSafeArea(.container, edges: .all)
        }.clipoScreenBackground(.black).overlay(alignment: .topLeading) {
            IconButton(symbol: .back, label: "Back") { dismiss() }.padding(12)
        }.preferredColorScheme(.dark)
            .onAppear { players.update(clips: route.clips, selectedID: activeID) }
            .onChange(of: activeID) { _, id in players.update(clips: route.clips, selectedID: id) }
            .onDisappear { players.releaseAll() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { players.suspend() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in players.trimMemory() }
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
    // Read from the enclosing safe container; video fills the expanded viewport.
    var controlInsets = EdgeInsets()
    @ObservedObject var playback: PlaybackController
    var didStartPlaying: () -> Void = {}
    @State private var visible = false
    @State private var firstFrameReady = false
    @State private var resumeAfterInterruption = false
    @State private var gate = false
    @State private var options = false
    @State private var editor = false
    @State private var share = false
    @State private var recorded = false
    @State private var allowed = false
    @State private var scrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var resumeAfterScrub = false
    var body: some View {
        ZStack {
            Color.black
            VideoSurface(player: playback.player, onReadyForDisplay: { firstFrameReady = $0 })
                .clipped().allowsHitTesting(false)
            if !firstFrameReady {
                MediaCover(url: clip.coverURL)
                    .allowsHitTesting(false)
            }
            Color.clear.contentShape(Rectangle()).onTapGesture {
                guard active, phase == .active, !ads.isPresenting else { return }
                if allowed { playback.toggle() } else { gate = true }
            }
            // Original raster scrim: a soft fade, never a hard panel across the video.
            Color.clear.overlay {
                Image("ClipoPlayerScrim").resizable().scaledToFill()
            }.clipped().allowsHitTesting(false).accessibilityHidden(true)
            if let error = playback.error {
                MessagePanel(title: "This clip couldn’t load", message: error, actionTitle: "Retry") { activate(reload: true) }.padding(24)
            } else if !allowed, active {
                VStack(spacing: 16) {
                    Text("Keep watching").font(.title.bold())
                    ActionButton(title: "Get more views") { gate = true }
                }.padding(32).background(ClipoStyle.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 24)).padding(24)
            } else if active, allowed, !playback.isPlaying, !playback.isLoading, !scrubbing {
                IconButton(symbol: .play, label: "Play video") { playback.play() }
                    .background(Color.black.opacity(0.4), in: Circle())
            }
            playerControls
            if active, playback.isLoading { Text("Loading…").font(.caption).padding(12).background(.black.opacity(0.6), in: Capsule()) }
        }.foregroundStyle(.white).clipped()
            .onAppear { visible = true; if active { activate() } }
            .onChange(of: active) { _, active in
                resumeAfterInterruption = false
                if active { activate() } else { playback.pause() }
            }
            .onChange(of: playback.isPlaying) { _, playing in
                if playing, active, visible, !recorded {
                    recorded = quota.recordWatch(clip.id, premium: commerce.premium)
                    if !recorded { playback.pause(); allowed = false; gate = true }
                }
                if playing, active, recorded { didStartPlaying() }
            }
            .onChange(of: phase) { _, state in
                if state != .active { interruptPlayback() } else { resumeIfNeeded() }
            }
            .onChange(of: ads.isPresenting) { _, presenting in
                if presenting { interruptPlayback() } else { resumeIfNeeded() }
            }
            .onDisappear { visible = false; resumeAfterInterruption = false; playback.pause() }
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
                    Text("Supported streams adjust quality to your connection.").font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                    ActionButton(title: "Edit a local video", primary: false) { options = false; editor = true }
                    Text("Online streams stay online. Import a video you own to make an edit.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
                    Spacer()
                }.padding(22).clipoScreenBackground().presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $editor) { EditorSheet() }
            .sheet(isPresented: $share) { ShareSheet(items: [WebAddress.media(clip.shortLink) ?? clip.playbackURL]) }
    }
    private var playerControls: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                IconButton(symbol: playback.muted ? .mute : .sound,
                           label: playback.muted ? "Unmute" : "Mute") {
                    playback.setMuted(!playback.muted)
                }
            }.padding(.top, 12)
            Spacer(minLength: 16)
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    if !clip.channel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(clip.channel).font(.subheadline.weight(.bold)).lineLimit(2)
                    }
                    Text(clip.title).font(.subheadline).lineLimit(2)
                        .accessibilityLabel(clip.title)
                }
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
                VStack(spacing: 16) {
                    PlayerRailButton(artwork: library.isSaved(clip) ? .saved : .save,
                                     title: library.isSaved(clip) ? "Saved" : "Save",
                                     accessibilityTitle: library.isSaved(clip) ? "Remove saved video" : "Save video",
                                     selected: library.isSaved(clip), action: save)
                    PlayerRailButton(artwork: .share, title: "Share", accessibilityTitle: "Share video link") {
                        playback.pause(); share = true
                    }
                    PlayerRailButton(artwork: .more, title: "More", accessibilityTitle: "Playback options") {
                        playback.pause(); options = true
                    }
                }.padding(.bottom, 8)
            }.padding(.leading, 4)
            ClipoScrubber(value: Binding(
                get: { scrubbing ? scrubPosition : playback.elapsed },
                set: {
                    scrubPosition = $0
                    // During a drag, move the UI only. Seek once on release.
                    if !scrubbing { playback.seek($0) }
                }
            ), range: 0...max(1, playback.duration), label: "Playback position",
                         tint: .white, trackHeight: scrubbing ? 5 : 2,
                         onEditingChanged: { editing in
                if editing {
                    scrubPosition = playback.elapsed
                    resumeAfterScrub = playback.isPlaying
                    scrubbing = true
                    playback.pause()
                } else {
                    playback.seek(scrubPosition)
                    scrubbing = false
                    if resumeAfterScrub && active && allowed && phase == .active && !ads.isPresenting {
                        playback.play()
                    }
                    resumeAfterScrub = false
                }
            })
            .disabled(!allowed || playback.duration <= 0 || playback.error != nil)
            .overlay(alignment: .top) {
                if scrubbing {
                    Text("\(durationLabel(scrubPosition)) / \(durationLabel(playback.duration))")
                        .font(.caption.monospacedDigit()).offset(y: -8)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
        .padding(controlInsets)
    }
    private func activate(reload: Bool = false) {
        guard active, visible, phase == .active, !ads.isPresenting,
              !options, !editor, !share else { return }
        recorded = false
        allowed = quota.mayWatch(clip.id, premium: commerce.premium)
        if !allowed { playback.pause(); gate = true; return }
        if playback.loadedURL != clip.playbackURL || reload { playback.load(clip.playbackURL, autoplay: true) }
        else { playback.play() }
    }
    private func interruptPlayback() {
        if active, visible, playback.intendsPlayback { resumeAfterInterruption = true }
        playback.pause()
    }
    private func resumeIfNeeded() {
        guard resumeAfterInterruption, active, visible, phase == .active,
              !ads.isPresenting, !gate, !options, !editor, !share else { return }
        resumeAfterInterruption = false
        activate()
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
    var tint: Color = ClipoStyle.accent
    var trackHeight: CGFloat = 4
    var onEditingChanged: (Bool) -> Void = { _ in }
    @GestureState private var dragging = false
    @State private var editing = false
    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard value.isFinite, range.lowerBound.isFinite, span.isFinite, span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3)).frame(height: trackHeight)
                Capsule().fill(tint).frame(width: geometry.size.width * fraction, height: trackHeight)
            }.frame(height: 44).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).updating($dragging) { _, state, _ in state = true }.onChanged { gesture in
                    if !editing { editing = true; onEditingChanged(true) }
                    value = range.lowerBound + min(1, max(0, gesture.location.x / max(1, geometry.size.width))) * (range.upperBound - range.lowerBound)
                }.onEnded { _ in finishEditing() })
        }.frame(height: 44).accessibilityElement().accessibilityLabel(label)
            .onChange(of: dragging) { _, dragging in if !dragging { finishEditing() } }
            .accessibilityValue(durationLabel(value)).accessibilityAdjustableAction { direction in
                value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? 1 : -1)))
            }
    }
    private func finishEditing() {
        guard editing else { return }
        editing = false
        onEditingChanged(false)
    }
}

private enum PlayerArtwork {
    case save, saved, share, more
    // Optical crop regions measured from the generated 1254px atlas.
    var region: CGRect {
        switch self {
        case .save: CGRect(x: 162.5, y: 179, width: 368, height: 368)
        case .saved: CGRect(x: 725.5, y: 177, width: 368, height: 368)
        case .share: CGRect(x: 145, y: 688, width: 400, height: 400)
        case .more: CGRect(x: 717.5, y: 698.5, width: 400, height: 400)
        }
    }
}

private struct PlayerRailButton: View {
    let artwork: PlayerArtwork
    let title: String
    let accessibilityTitle: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                GeometryReader { geometry in
                    let rect = artwork.region
                    Image("ClipoPlayerActions").resizable().interpolation(.high)
                        .colorMultiply(selected ? ClipoStyle.accent : .white)
                        .frame(width: 1254 * geometry.size.width / rect.width,
                               height: 1254 * geometry.size.height / rect.height)
                        .offset(x: -rect.minX * geometry.size.width / rect.width,
                                y: -rect.minY * geometry.size.height / rect.height)
                }.frame(width: 36, height: 36).clipped().blendMode(.screen)
                    .allowsHitTesting(false)
                Text(title).font(.caption2.weight(.medium)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            }.frame(minWidth: 48, minHeight: 54)
                .contentShape(.interaction, Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityLabel(accessibilityTitle)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

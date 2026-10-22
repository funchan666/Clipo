import SwiftUI

@MainActor
final class FeedStore: ObservableObject {
    @Published private(set) var entries: [PlaybackQueueEntry]
    @Published private(set) var loading = false
    @Published private(set) var hasMore = true
    @Published var error: String?
    var clips: [LessonClip] { entries.map(\.clip) }
    private var feedID: String?
    private var cursor: String?
    private var roundVideoIDs = Set<String>()
    private var requestQuery = ""
    private(set) var query = ""
    private var generation = UUID()

    init(seed: [LessonClip] = []) {
        entries = seed.map { PlaybackQueueEntry(id: $0.id, clip: $0) }
        hasMore = seed.isEmpty
    }

    func invalidatePendingLoad() {
        generation = UUID()
        loading = false
    }

    func isNearEnd(_ id: String?) -> Bool {
        guard let id, let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        return index >= entries.count - 3
    }

    func load(api: APIClient, search: String? = nil) async {
        if let search {
            generation = UUID()
            entries = []; feedID = nil; cursor = nil; hasMore = true; loading = false
            query = search; requestQuery = search; roundVideoIDs = []
        }
        guard !loading else { return }
        let current = generation
        loading = true
        error = nil
        defer { if generation == current { loading = false } }
        do {
            // Skip a few duplicate/invalid pages, but never spin on an empty service.
            for _ in 0..<3 {
                if !hasMore {
                    feedID = nil; cursor = nil; roundVideoIDs = []
                    requestQuery = "" // Finished search/collection -> fresh recommendation round.
                    hasMore = true
                }
                let previousCursor = cursor
                let response = try await api.feed(query: requestQuery, feedID: feedID, cursor: cursor)
                try Task.checkCancellation()
                guard current == generation else { return }
                let additions = response.list.compactMap(\.clip).filter { roundVideoIDs.insert($0.id).inserted }
                    .map { PlaybackQueueEntry(id: UUID().uuidString, clip: $0) }
                feedID = response.feedId?.nilIfBlank
                cursor = response.nextCursor?.nilIfBlank
                hasMore = response.hasMore && cursor != nil && cursor != previousCursor
                if !additions.isEmpty { entries += additions; return }
                if response.list.isEmpty { hasMore = false; break }
            }
            if !entries.isEmpty { error = "No more lessons are available right now. Try again." }
        } catch is CancellationError {
            // Leaving a screen/search is not a service failure.
        } catch {
            if current == generation, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
struct DiscoverView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    private let canDismiss: Bool
    private let onExit: (() -> Void)?
    private let onSearchResult: ((String, LessonClip) -> Void)?
    @EnvironmentObject private var offline: OfflineStore
    private var displayEntries: [PlaybackQueueEntry] {
        feed.entries.map { PlaybackQueueEntry(id: $0.id, clip: offline.playable($0.clip)) }
    }
    private let morePageID = "recommendation-tail"
    @EnvironmentObject private var api: APIClient
    @StateObject private var feed = FeedStore()
    @StateObject private var players = PlaybackPool()
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var visible = false
    @State private var activeID: String?
    @State private var recordedQuery: String?
    init(initialSearch: String = "", canDismiss: Bool = false, onExit: (() -> Void)? = nil,
         onSearchResult: ((String, LessonClip) -> Void)? = nil) {
        self.canDismiss = canDismiss
        self.onExit = onExit
        self.onSearchResult = onSearchResult
        _search = State(initialValue: initialSearch)
    }
    var body: some View {
        ZStack(alignment: .top) {
            if api.session == nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        TennisArtwork(kind: .lesson, height: 208)
                        LocalizedText("Connecting your lesson feed…")
                            .font(.court(.subheadline)).foregroundStyle(ClipoStyle.secondary)
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
                                ForEach(displayEntries) { entry in
                                    let clip = entry.clip
                                    Group {
                                        if let playback = players.controllers[entry.id] {
                                            ClipPage(clip: clip, active: activeID == entry.id,
                                                     controlInsets: container.safeAreaInsets, playback: playback,
                                                     didStartPlaying: { players.prepareNext(after: entry.id) },
                                                     didStopPlaying: { if activeID == entry.id { players.suspend() } },
                                                     onSwipeExit: exitPlayer)
                                        } else {
                                            PlayerPoster(url: clip.coverURL)
                                        }
                                    }.frame(width: geometry.size.width, height: geometry.size.height).clipped().id(entry.id)
                                }
                                if !feed.entries.isEmpty {
                                    VStack(spacing: 16) {
                                        LocalizedText(feed.error ?? "Finding more clips…").foregroundStyle(ClipoStyle.secondary)
                                        ActionButton(title: "Load more", primary: false, busy: feed.loading) { Task { await feed.load(api: api) } }
                                    }.padding(28).padding(container.safeAreaInsets)
                                        .frame(width: geometry.size.width, height: geometry.size.height).id(morePageID)
                                }
                            }.scrollTargetLayout()
                        }.scrollTargetBehavior(.paging).scrollPosition(id: $activeID, anchor: .top).scrollIndicators(.hidden)
                            .onChange(of: activeID) { _, id in
                                players.update(entries: displayEntries, selectedID: id)
                            }
                    }.ignoresSafeArea(.container, edges: .all)
                }
            }
            if api.session != nil, !feed.clips.isEmpty {
                feedHeader
            }
        }.clipoScreenBackground(.black)
            .modifier(PlayerPagingAccess(entries: displayEntries, selectedID: $activeID, tailID: morePageID, players: players))
            .overlay(alignment: .top) { DownloadCompletionNotice().padding(.top, 56) }
            .onChange(of: library.downloadsRequest) { _, request in
                if request != nil { players.releaseAll(); if canDismiss { dismiss() } }
            }
            .onAppear { visible = true; players.update(entries: displayEntries, selectedID: activeID) }
            .task(id: api.session?.userId.value) {
                guard api.session != nil else { return }
                await feed.load(api: api, search: search)
                guard !Task.isCancelled else { return }
                activeID = feed.entries.first?.id
            }
            .onChange(of: activeID) { _, id in
                guard visible, api.session != nil,
                      id == morePageID || feed.isNearEnd(id) else { return }
                Task { guard visible else { return }; await feed.load(api: api) }
            }
            .onChange(of: feed.entries) { previous, entries in
                guard visible else { return }
                if activeID == morePageID, entries.count > previous.count {
                    activeID = entries[previous.count].id
                } else if !entries.contains(where: { $0.id == activeID }) { activeID = entries.first?.id }
                players.update(entries: displayEntries, selectedID: activeID)
                if let first = entries.first?.clip, recordedQuery != feed.query {
                    recordedQuery = feed.query
                    onSearchResult?(feed.query, first)
                }
            }
            .onDisappear { visible = false; feed.invalidatePendingLoad(); players.releaseAll() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { players.suspend() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in players.trimMemory() }
    }
    private var feedHeader: some View {
        HStack {
            Spacer(minLength: 0)
            if canDismiss || onExit != nil {
                PlayerExitButton(action: exitPlayer)
            }
        }.environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, 12).padding(.top, 8)
    }
    private func exitPlayer() {
        guard canDismiss || onExit != nil else { return }
        players.releaseAll()
        if let onExit { onExit() } else { dismiss() }
    }

}

struct PlayerScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    let route: PlayerRoute
    @State private var visible = false
    @State private var activeID: String?
    @StateObject private var feed: FeedStore
    @StateObject private var players = PlaybackPool()
    @Environment(\.scenePhase) private var scenePhase
    private let morePageID = "collection-recommendation-tail"
    private var displayEntries: [PlaybackQueueEntry] {
        feed.entries.map { PlaybackQueueEntry(id: $0.id, clip: offline.playable($0.clip)) }
    }
    init(route: PlayerRoute) {
        self.route = route
        _activeID = State(initialValue: route.startID)
        _feed = StateObject(wrappedValue: FeedStore(seed: route.clips))
    }
    var body: some View {
        GeometryReader { container in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(displayEntries) { entry in
                            let clip = entry.clip
                            Group {
                                if let playback = players.controllers[entry.id] {
                                    ClipPage(clip: clip, active: activeID == entry.id,
                                             supportsPaging: displayEntries.count > 1 || route.continuesRecommendations,
                                             controlInsets: container.safeAreaInsets, playback: playback,
                                             didStartPlaying: { players.prepareNext(after: entry.id) },
                                             didStopPlaying: { if activeID == entry.id { players.suspend() } },
                                             onSwipeExit: exitPlayer)
                                } else { PlayerPoster(url: clip.coverURL) }
                            }.containerRelativeFrame([.horizontal, .vertical]).clipped().id(entry.id)
                        }
                        if route.continuesRecommendations {
                            VStack(spacing: 16) {
                                LocalizedText(feed.error ?? "Finding more clips…")
                                ActionButton(title: "Load more", primary: false, busy: feed.loading) {
                                    Task { await feed.load(api: api) }
                                }
                            }.padding(28).padding(container.safeAreaInsets)
                                .containerRelativeFrame([.horizontal, .vertical]).id(morePageID)
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging).scrollPosition(id: $activeID, anchor: .top)
                .scrollIndicators(.hidden)
                .task { proxy.scrollTo(route.startID, anchor: .top) }
            }.ignoresSafeArea(.container, edges: .all)
        }.clipoScreenBackground(.black).overlay(alignment: .top) {
            HStack {
                Spacer(minLength: 0)
                PlayerExitButton(action: exitPlayer)
            }.environment(\.layoutDirection, .leftToRight)
                .padding(.horizontal, 12).padding(.top, 8)
        }.preferredColorScheme(.dark)
            .overlay(alignment: .top) { DownloadCompletionNotice().padding(.top, 56) }
            .onChange(of: library.downloadsRequest) { _, request in if request != nil { exitPlayer() } }
            .modifier(PlayerPagingAccess(entries: displayEntries, selectedID: $activeID, tailID: morePageID, players: players))
            .onAppear {
                visible = true
                players.update(entries: displayEntries, selectedID: activeID)
                continueFeedIfNeeded(activeID)
            }
            .onChange(of: activeID) { _, id in
                players.update(entries: displayEntries, selectedID: id)
                continueFeedIfNeeded(id)
            }
            .onChange(of: feed.entries) { previous, entries in
                guard visible else { return }
                if activeID == morePageID, entries.count > previous.count { activeID = entries[previous.count].id }
                players.update(entries: displayEntries, selectedID: activeID)
            }
            .onDisappear { visible = false; feed.invalidatePendingLoad(); players.releaseAll() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { players.suspend() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in players.trimMemory() }
    }
    private func exitPlayer() {
        players.releaseAll()
        dismiss()
    }
    private func continueFeedIfNeeded(_ id: String?) {
        guard visible, route.continuesRecommendations, id == morePageID || feed.isNearEnd(id) else { return }
        Task { guard visible else { return }; await feed.load(api: api) }
    }
}

private struct PlaybackGateKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
    var playbackGatePresented: Bool {
        get { self[PlaybackGateKey.self] }
        set { self[PlaybackGateKey.self] = newValue }
    }
}

// Enforce admission at the paging boundary, so denied pages cannot strand the
// user on a succession of unplayable videos. Returning to admitted clips is free.
private struct PlayerPagingAccess: ViewModifier {
    let entries: [PlaybackQueueEntry]
    @Binding var selectedID: String?
    let tailID: String
    @ObservedObject var players: PlaybackPool
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var admittedID: String?
    @State private var requestedID: String?
    @State private var showingReward = false
    @State private var swipeOrigin: String?
    @State private var trackingSwipe = false
    @State private var swipeEnded: UUID?
    @AppStorage("player.completedSwipeHint.v6") private var completedHint = false

    func body(content: Content) -> some View {
        content
            .environment(\.playbackGatePresented, showingReward)
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { value in
                guard !showingReward, abs(value.translation.height) > abs(value.translation.width) else { return }
                if !trackingSwipe { trackingSwipe = true; swipeOrigin = admittedID; swipeEnded = nil }
            }.onEnded { _ in swipeEnded = UUID() })
            .task(id: swipeEnded) {
                guard swipeEnded != nil else { return }
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                trackingSwipe = false; swipeOrigin = nil
            }
            .onAppear { admit(selectedID) }
            .onChange(of: selectedID) { _, value in admit(value) }
            .sheet(isPresented: $showingReward, onDismiss: finishReward) {
                MembershipView(rewardKind: .watch)
            }
    }
    private func canWatch(_ id: String) -> Bool {
        guard let clip = entries.first(where: { $0.id == id })?.clip else { return false }
        return clip.playbackURL.isFileURL || quota.mayWatch(clip.id, premium: commerce.premium)
    }
    private func admit(_ id: String?) {
        guard !showingReward, let id else { return }
        if let admittedID, !entries.contains(where: { $0.id == admittedID }) { self.admittedID = nil }
        let isTail = id == tailID
        if canWatch(id) || (isTail && !quota.canRequestReward(for: .watch, premium: commerce.premium)) {
            if !isTail {
                if trackingSwipe, let swipeOrigin, swipeOrigin != id, admittedID != id {
                    completedHint = true
                }
                admittedID = id
            }
            return
        }
        guard isTail || entries.contains(where: { $0.id == id }) else { return }
        requestedID = id
        players.controllers.values.forEach { $0.pause() }
        players.suspend()
        if let admittedID, admittedID != id {
            // A new deliberate swipe may prompt again; dismissal itself never does.
            showingReward = true
            selectedID = admittedID
        } else {
            admittedID = id
            if quota.claimWatchLimitPrompt(premium: commerce.premium) { showingReward = true }
        }
    }
    private func finishReward() {
        if let requestedID, canWatch(requestedID) { selectedID = requestedID }
        requestedID = nil
    }
}

// Count the cue only after an uninterrupted presentation. The old flag could
// be consumed by buffering or a sheet before the user had time to read it.
private struct PlayerSwipeHint: View {
    let eligible: Bool
    @AppStorage("player.completedSwipeHint.v6") private var alreadyShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var showing = false
    var body: some View {
        // A persistent host is essential: a task on an empty conditional Group
        // has no rendered child to start it. Buffering must not gate this cue.
        GeometryReader { container in
            // The parent reserves the exit, action rail and bottom captions.
            // Size the artwork from the remaining viewport, not a device model.
            let width = max(0, container.size.width)
            let height = max(0, container.size.height)
            let artworkHeight = min(width * 1.18, height * 0.64, 520)
            ZStack {
                Color.clear
                if showing && eligible && !alreadyShown && phase == .active {
                    VStack(spacing: min(24, height * 0.04)) {
                        Color.clear.frame(width: width, height: artworkHeight)
                            .phaseAnimator([0, 1, 2, 3, 4]) { host, step in
                                host.overlay {
                                    let resting = step == 0 || step == 4
                                    ZStack {
                                        Image("ClipoSwipeTrail").resizable().scaledToFit()
                                            .frame(width: artworkHeight * 0.56, height: artworkHeight)
                                            .offset(x: -artworkHeight * 0.12)
                                            .opacity(reduceMotion ? 0.7 : (resting ? 0.25 : 0.9))
                                            .scaleEffect(reduceMotion || resting ? 0.94 : 1)
                                        Image("ClipoSwipeGesture").resizable().scaledToFit()
                                            .frame(width: artworkHeight * 0.48, height: artworkHeight * 0.48)
                                            .shadow(color: ClipoStyle.accent.opacity(0.25), radius: 6)
                                            .rotationEffect(.degrees(reduceMotion ? 0 : (step == 2 ? -5 : 3)))
                                            .offset(x: artworkHeight * 0.1,
                                                    y: reduceMotion ? 0 : (step == 2 ? -1 : 1) * artworkHeight * 0.22)
                                            .opacity(reduceMotion ? 1 : (resting ? 0.15 : 1))
                                    }
                                }
                            } animation: { step in
                                reduceMotion ? nil : .easeInOut(duration: step == 2 || step == 3 ? 0.85 : 0.3)
                            }
                        LocalizedText("Swipe up or down to change videos")
                            .font(.court(.title3, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .shadow(color: .black.opacity(0.8), radius: 4, y: 1)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .transition(.opacity)
                }
            }.frame(width: width, height: height)
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showing)
        .task(id: eligible && phase == .active) {
            showing = false
            guard eligible, phase == .active, !alreadyShown else { return }
            do {
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                showing = true
                try await Task.sleep(for: .seconds(6))
                try Task.checkCancellation()
                alreadyShown = true
            } catch { }
            showing = false
        }
    }
}

struct ClipPage: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.scenePhase) private var phase
    @Environment(\.playbackGatePresented) private var pagingGate
    let clip: LessonClip
    let active: Bool
    var supportsPaging = true
    // Read from the enclosing safe container; video fills the expanded viewport.
    var controlInsets = EdgeInsets()
    @ObservedObject var playback: PlaybackController
    var didStartPlaying: () -> Void = {}
    var didStopPlaying: () -> Void = {}
    var onSwipeExit: () -> Void = {}
    @State private var visible = false
    @State private var firstFrameReady = false
    @State private var accessChecked = false
    @State private var resumeAfterSheet = false
    @State private var resumeAfterInterruption = false
    @State private var gate = false
    @State private var options = false
    @State private var editor = false
    @State private var downloadPanel = false
    @State private var downloadStarting = false
    @State private var downloadReward = false
    @State private var recorded = false
    @State private var allowed = false
    @State private var scrubbing = false
    @State private var favoriteError: String?
    var body: some View {
        ZStack {
            Color.black
            VideoSurface(player: playback.player, onReadyForDisplay: { firstFrameReady = $0 })
                .clipped().allowsHitTesting(false)
            if !firstFrameReady {
                PlayerPoster(url: clip.coverURL)
                    .allowsHitTesting(false)
            }
            Color.clear.contentShape(Rectangle()).onTapGesture {
                guard active, phase == .active, !ads.isPresenting else { return }
                if allowed, firstFrameReady { playback.toggle() }
            }
            // Only the video backdrop owns this gesture; controls and the
            // scrubber above it keep their own touches. Vertical paging wins
            // unless the completed gesture is decisively leftward.
            .simultaneousGesture(DragGesture(minimumDistance: 32).onEnded { value in
                guard active, visible, phase == .active, !ads.isPresenting,
                      !pagingGate, !gate, !options, !editor, !downloadPanel,
                      !downloadReward, !scrubbing,
                      value.translation.width < -90,
                      abs(value.translation.width) > abs(value.translation.height) * 1.7 else { return }
                onSwipeExit()
            })
            // Original raster scrim: a soft fade, never a hard panel across the video.
            Color.clear.overlay {
                Image("ClipoPlayerScrim").resizable().scaledToFill()
            }.clipped().allowsHitTesting(false).accessibilityHidden(true)
            playerControls
            if active, let favoriteError {
                VStack {
                    HStack(spacing: 10) {
                        LocalizedText(favoriteError).font(.court(.caption))
                        IconButton(symbol: .close, label: "Dismiss message") { self.favoriteError = nil }
                    }.padding(12).background { OriginalSurface(tone: .pine) }
                    Spacer()
                }.padding(.top, controlInsets.top + 60).padding(.horizontal, 16)
            }
            PlayerSwipeHint(eligible: supportsPaging && active && visible && playback.error == nil &&
                            !pagingGate && !gate && !options && !editor && !downloadPanel && !downloadReward && !ads.isPresenting)
                .padding(.top, controlInsets.top + 64)
                .padding(.bottom, controlInsets.bottom + 150)
                .padding(.leading, controlInsets.leading + 20)
                .padding(.trailing, controlInsets.trailing + 72)
            if active, visible, !pagingGate, !gate, !options, !editor, !downloadPanel, !downloadReward {
                if accessChecked, !allowed {
                    VStack(spacing: 16) {
                        LocalizedText("Keep watching").font(.court(.title3, weight: .semibold))
                        ActionButton(title: "Get more views") { gate = true }
                    }.padding(20).frame(maxWidth: 320)
                        .background { OriginalSurface(tone: .pine) }.padding(24)
                } else if let error = playback.error {
                    MessagePanel(title: "This clip couldn’t load", message: error, actionTitle: "Retry") { activate(reload: true) }.padding(24)
                } else if allowed, playback.isLoading || (!firstFrameReady && playback.intendsPlayback) {
                    PlayerLoadingFeedback(buffering: firstFrameReady)
                        .allowsHitTesting(false)
                } else if allowed, firstFrameReady, !playback.intendsPlayback, !scrubbing {
                    IconButton(symbol: .play, label: "Play video") { playback.play() }
                        .shadow(color: .black.opacity(0.65), radius: 3, y: 1)
                }
            }
        }.foregroundStyle(.white).clipped()
            .onAppear { visible = true; if active { activate() } }
            .onChange(of: active) { _, active in
                resumeAfterInterruption = false
                if active { activate() } else { favoriteError = nil; resumeAfterSheet = false; playback.pause() }
            }
            .onChange(of: playback.isPlaying) { _, playing in
                if playing, active, visible, !recorded {
                    recorded = clip.playbackURL.isFileURL || quota.recordWatch(clip.id, premium: commerce.premium)
                    if !recorded { playback.pause(); allowed = false }
                }
                if playing, active, recorded { didStartPlaying() }
                if !playing, active { didStopPlaying() }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                guard active, visible, playback.isPlaying, !clip.playbackURL.isFileURL else { return }
                if !quota.recordWatch(clip.id, premium: commerce.premium) { playback.pause(); allowed = false }
            }
            .onChange(of: phase) { _, state in
                if state != .active { interruptPlayback() } else { resumeIfNeeded() }
            }
            .onChange(of: ads.isPresenting) { _, presenting in
                if presenting { interruptPlayback() } else { resumeIfNeeded() }
            }
            .onDisappear { visible = false; resumeAfterInterruption = false; playback.pause() }
            .onChange(of: library.downloadsRequest) { _, request in
                if request != nil { options = false; downloadPanel = false; editor = false }
            }
            .onChange(of: gate) { _, presented in if presented { playback.pause() } }
            .onChange(of: pagingGate) { _, presented in
                if presented { playback.pause() } else if active { activate() }
            }
            .sheet(isPresented: $gate, onDismiss: { if active { activate() } }) { MembershipView(rewardKind: .watch) }
            .sheet(isPresented: $options, onDismiss: resumeAfterControls) {
                ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHeading(title: "Playback") { options = false }
                    VideoExportEntry(clip: clip)
                    LocalizedText("Speed").font(.court(.headline))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([Float(0.5), 1, 1.5, 2], id: \.self) { speed in
                                Button("\(speed, specifier: "%g")×") { playback.setSpeed(speed) }
                                    .font(.court(.subheadline, weight: .semibold))
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 16).frame(minHeight: 44)
                                    .foregroundStyle(playback.speed == speed ? ClipoStyle.ink : ClipoStyle.paper)
                                    .background { OriginalSurface(tone: playback.speed == speed ? .accent : .pine) }
                                    .accessibilityAddTraits(playback.speed == speed ? .isSelected : [])
                            }
                        }
                    }.buttonStyle(PressStyle())
                    LocalizedText("Supported streams adjust quality to your connection.").font(.court(.subheadline)).foregroundStyle(ClipoStyle.secondary)
                    ActionButton(title: "Edit a local video", primary: false) { options = false; editor = true }
                    OfflineDownloadButton(clip: clip)
                    Spacer()
                }.padding(22)
                }.clipoScreenBackground().presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $editor, onDismiss: resumeAfterControls) { EditorSheet() }
            .sheet(isPresented: $downloadPanel, onDismiss: resumeAfterControls) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SheetHeading(title: "Downloads") { downloadPanel = false }
                        Text(verbatim: clip.title).font(.court(.subheadline)).lineLimit(2)
                        OfflineDownloadButton(clip: clip, starting: downloadStarting)
                    }.padding(22)
                }.clipoScreenBackground().presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $downloadReward, onDismiss: resumeAfterControls) { MembershipView(rewardKind: .download) }
    }
    private var playerControls: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    if !clip.channel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(verbatim: clip.channel).font(.court(.subheadline, weight: .bold)).lineLimit(2)
                    }
                    Text(verbatim: clip.title).font(.court(.subheadline)).lineLimit(2)
                        .accessibilityLabel(clip.title)
                }
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
                VStack(spacing: 8) {
                    PlayerRailButton(artwork: library.isSaved(clip) ? .saved : .save,
                                     title: library.isSaved(clip) ? "Favorited" : "Favorite",
                                     accessibilityTitle: library.isSaved(clip) ? "Remove saved video" : "Save video",
                                     selected: library.isSaved(clip), action: save)
                    PlayerCacheButton(clip: clip, action: cacheVideo)
                    PlayerRailButton(artwork: .more, title: "More", accessibilityTitle: "Playback options") {
                        resumeAfterSheet = playback.intendsPlayback
                        playback.pause(); options = true
                    }
                }.padding(.bottom, 8)
            }.padding(.leading, 4)
            PlayerProgressControl(playback: playback, timeline: playback.timeline,
                                  enabled: allowed && firstFrameReady,
                                  canResume: active && allowed && phase == .active && !ads.isPresenting,
                                  scrubbing: $scrubbing)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
        .padding(controlInsets)
    }
    private func activate(reload: Bool = false) {
        guard active, visible, phase == .active, !ads.isPresenting, !pagingGate,
              !gate, !options, !editor, !downloadPanel, !downloadReward else { return }
        recorded = false
        accessChecked = true
        allowed = clip.playbackURL.isFileURL || quota.mayWatch(clip.id, premium: commerce.premium)
        if !allowed {
            playback.pause()
            // Paging owns automatic prompts; this page retains the explicit reward action.
            return
        }
        if playback.loadedURL != clip.playbackURL || reload {
            firstFrameReady = false
            playback.load(clip.playbackURL, autoplay: true)
        }
        else { playback.play() }
    }
    private func resumeAfterControls() {
        guard resumeAfterSheet, active, visible, phase == .active,
              !ads.isPresenting, !gate, !options, !editor, !downloadPanel, !downloadReward else { return }
        resumeAfterSheet = false
        activate()
    }
    private func interruptPlayback() {
        if active, visible, playback.intendsPlayback { resumeAfterInterruption = true }
        playback.pause()
    }
    private func resumeIfNeeded() {
        guard resumeAfterInterruption || resumeAfterSheet, active, visible, phase == .active,
              !ads.isPresenting, !gate, !options, !editor, !downloadPanel, !downloadReward else { return }
        resumeAfterInterruption = false
        resumeAfterSheet = false
        activate()
    }
    private func cacheVideo() {
        // Acknowledge every tap before starting asynchronous preparation. The
        // presented panel observes the store through completion and late errors.
        if downloadStarting || offline.cached(clip.id) != nil || offline.busy || clip.playbackURL.isFileURL {
            showDownloadPanel()
        } else if !quota.mayDownload(clip.id, premium: commerce.premium) {
            resumeAfterSheet = playback.intendsPlayback
            playback.pause(); downloadReward = true
        } else {
            downloadStarting = true
            showDownloadPanel()
            Task { @MainActor in
                defer { downloadStarting = false }
                await offline.download(clip)
            }
        }
    }
    private func showDownloadPanel() {
        guard !downloadPanel else { return }
        resumeAfterSheet = playback.intendsPlayback
        playback.pause(); downloadPanel = true
    }
    private func save() {
        favoriteError = nil
        if !library.toggle(offline.cached(clip.id)?.clip ?? clip) {
            favoriteError = "Favorites could not be updated. Please try again."
            library.error = nil // This full-screen surface owns the feedback.
        }
    }
}
private struct PlayerExitButton: View {
    let action: () -> Void
    private static let artwork: UIImage? = {
        guard let source = UIImage(named: "CourtExitControl")?.cgImage else { return nil }
        let scale = CGFloat(source.width) / 2022
        let bounds = CGRect(x: 89, y: 145, width: 1846, height: 458)
            .applying(CGAffineTransform(scaleX: scale, y: scale)).integral
        guard let image = source.cropping(to: bounds) else { return nil }
        return UIImage(cgImage: image, scale: 4, orientation: .up)
    }()
    var body: some View {
        Button(action: action) {
            LocalizedText("Exit").font(.court(.caption, weight: .semibold))
                .foregroundStyle(ClipoStyle.paper).lineLimit(1).minimumScaleFactor(0.75)
                .padding(.leading, 10).padding(.trailing, 27)
                .frame(width: 78, height: 30)
                .background {
                    if let artwork = Self.artwork {
                        Image(uiImage: artwork).resizable(capInsets: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 32))
                    }
                }
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityLabel(LocalizedStringKey("Exit"))
    }
}

private struct PlayerCacheButton: View {
    let clip: LessonClip
    let action: () -> Void
    @EnvironmentObject private var offline: OfflineStore
    private var cached: Bool { offline.cached(clip.id) != nil || clip.playbackURL.isFileURL }
    var body: some View {
        Button(action: action) {
            PlayerRailLabel(artwork: .download, selected: cached) {
                if cached { LocalizedText("Offline") }
                else if offline.preparingID == clip.id { LocalizedText("Loading…") }
                else if offline.downloadingID == clip.id { Text(verbatim: "\(Int(offline.progress * 100))%") }
                else { LocalizedText("Download") }
            }
        }.buttonStyle(PressStyle())
            .accessibilityLabel(LocalizedStringKey(cached ? "Available offline" : "Download for offline"))
            .accessibilityIdentifier("player.cacheVideo")
    }
}

private struct PlayerProgressControl: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var timeline: PlaybackTimeline
    let enabled: Bool
    let canResume: Bool
    @Binding var scrubbing: Bool
    @State private var scrubPosition: Double = 0
    @State private var resumeAfterScrub = false
    var body: some View {
        ClipoScrubber(value: Binding(
                get: { scrubbing ? scrubPosition : timeline.elapsed },
                set: {
                    scrubPosition = $0
                    // During a drag, move the UI only. Seek once on release.
                    if !scrubbing { playback.seek($0) }
                }
            ), range: 0...max(1, timeline.duration), label: "Playback position",
                         tint: .white, trackHeight: scrubbing ? 5 : 2,
                         onEditingChanged: { editing in
                if editing {
                    scrubPosition = timeline.elapsed
                    resumeAfterScrub = playback.isPlaying
                    scrubbing = true
                    playback.pause()
                } else {
                    playback.seek(scrubPosition)
                    scrubbing = false
                    if resumeAfterScrub && canResume {
                        playback.play()
                    }
                    resumeAfterScrub = false
                }
            })
            .disabled(!enabled || timeline.duration <= 0 || playback.error != nil)
            .overlay(alignment: .top) {
                if scrubbing {
                    Text(verbatim: "\(durationLabel(scrubPosition)) / \(durationLabel(timeline.duration))")
                        .environment(\.layoutDirection, .leftToRight)
                        .font(.caption.monospacedDigit()).offset(y: -8)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct PlayerPoster: View {
    let url: URL?
    var body: some View {
        Color.black.overlay {
            GeometryReader { geometry in
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        }
                    }
                }
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct PlayerLoadingFeedback: View {
    let buffering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var revealed = false
    var body: some View {
        VStack(spacing: 10) {
            Image("ClipoLoadingMark").resizable().scaledToFit()
                .frame(width: 36, height: 5)
                .phaseAnimator([false, true]) { content, dimmed in
                    content.opacity(reduceMotion || phase != .active ? 1 : (dimmed ? 0.3 : 1))
                } animation: { _ in
                    reduceMotion || phase != .active ? nil : .easeInOut(duration: 0.6)
                }.accessibilityHidden(true)
            LocalizedText(buffering ? "Buffering…" : "Loading…")
                .font(.court(.caption)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
        }.opacity(revealed ? 1 : 0).accessibilityHidden(!revealed)
            .task {
                do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); revealed = true }
                catch { }
            }
            .onDisappear { revealed = false }
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
        }.frame(height: 44).environment(\.layoutDirection, .leftToRight)
            .accessibilityElement().accessibilityLabel(LocalizedStringKey(label))
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

private enum PlayerArtwork: CaseIterable, Hashable {
    case save, saved, download, more
    // Tight optical bounds keep original glyphs centered despite unequal atlas padding.
    var region: CGRect {
        switch self {
        case .save: CGRect(x: 204, y: 196, width: 284, height: 334)
        case .saved: CGRect(x: 768, y: 194, width: 283, height: 333)
        case .download: CGRect(x: 972, y: 399, width: 200, height: 195)
        case .more: CGRect(x: 738, y: 846, width: 358, height: 105)
        }
    }
    private static let tiles: [PlayerArtwork: UIImage] = {
        return Dictionary(uniqueKeysWithValues: allCases.compactMap { artwork -> (PlayerArtwork, UIImage)? in
            let name = artwork == .download ? "ClipoGlyphAtlas" : "ClipoPlayerActions"
            guard let source = UIImage(named: name)?.cgImage else { return nil }
            let scale = CGFloat(source.width) / 1254
            let rect = artwork.region.applying(CGAffineTransform(scaleX: scale, y: scale)).integral
            guard let tile = source.cropping(to: rect) else { return nil }
            return (artwork, UIImage(cgImage: tile))
        })
    }()
    var image: UIImage? { Self.tiles[self] }

}

// Shared geometry for every rail action, including the changing cache status.
private struct PlayerRailLabel<Label: View>: View {
    let artwork: PlayerArtwork
    let selected: Bool
    private let label: Label
    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 16
    init(artwork: PlayerArtwork, selected: Bool, @ViewBuilder label: () -> Label) {
        self.artwork = artwork
        self.selected = selected
        self.label = label()
    }
    var body: some View {
        VStack(spacing: 4) {
            OriginalSymbolMask(image: artwork.image, tint: selected ? ClipoStyle.accent : .white)
                .frame(width: 24, height: 24)
                .frame(width: 28, height: 28)
            label.font(.court(.caption2, weight: .medium))
                .foregroundStyle(selected ? ClipoStyle.accent : .white)
                .lineLimit(1).minimumScaleFactor(0.65).multilineTextAlignment(.center)
                .frame(width: 48, height: labelHeight)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
        }.frame(width: 48, height: max(52, 32 + labelHeight))
            .contentShape(.interaction, Rectangle())
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
            PlayerRailLabel(artwork: artwork, selected: selected) {
                LocalizedText(title)
            }
        }.buttonStyle(PressStyle())
            .accessibilityLabel(LocalizedStringKey(accessibilityTitle))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

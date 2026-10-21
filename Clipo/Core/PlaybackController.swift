import AVFoundation
import SwiftUI

// Progress ticks belong to the scrubber, not the entire video/control hierarchy.
@MainActor
final class PlaybackTimeline: ObservableObject {
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
}

@MainActor
final class PlaybackController: ObservableObject {
    let player = AVPlayer()
    @Published var isPlaying = false
    @Published var isLoading = true
    @Published var error: String?
    let timeline = PlaybackTimeline()
    @Published var muted = false
    @Published var speed: Float = 1
    private(set) var loadedURL: URL?
    var intendsPlayback: Bool { wantsPlayback }
    private var status: NSKeyValueObservation?
    private var timeStatus: NSKeyValueObservation?
    private var playerStatus: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var timer: Any?
    @Published private var wantsPlayback = false
    private var warming = false
    private var generation = UUID()
    private var pendingSeek: Double?
    private var seeking = false
    private var loadingDeadline: Task<Void, Never>?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let item = self.player.currentItem else { return }
                // Read current state, rather than a time captured before an item switch.
                let seconds = self.player.currentTime().seconds
                let length = item.duration.seconds
                let elapsed = seconds.isFinite ? max(0, seconds) : 0
                let duration = length.isFinite ? max(0, length) : 0
                if !self.seeking, self.timeline.elapsed != elapsed { self.timeline.elapsed = elapsed }
                if self.timeline.duration != duration { self.timeline.duration = duration }
            }
        }
        timeStatus = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updatePlaybackState() }
        }
        playerStatus = player.observe(\.status, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.prerollIfReady() }
        }
    }
    func load(_ url: URL, autoplay: Bool) {
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        load(item, autoplay: autoplay)
        loadedURL = url
    }
    func load(_ item: AVPlayerItem, autoplay: Bool) {
        release()
        error = nil
        isLoading = true
        if wantsPlayback != autoplay { wantsPlayback = autoplay }
        // Zero leaves buffering/variant selection to AVFoundation for the active video.
        item.preferredForwardBufferDuration = 0
        player.replaceCurrentItem(with: item)
        let token = generation
        status = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.player.currentItem === observed else { return }
                if observed.status == .failed {
                    self.fail(observed.error?.localizedDescription ?? "This clip could not be played.")
                } else if observed.status == .readyToPlay {
                    if self.pendingSeek != nil { self.performPendingSeek() }
                    else if self.wantsPlayback { self.play() }
                    else { self.prerollIfReady() }
                }
                self.updatePlaybackState()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                // Seek completion resumes only if this page still intends to play.
                self.seek(0)
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.fail("Playback was interrupted. Check your connection and try again.")
            }
        }
    }
    func prepare(_ url: URL) {
        guard loadedURL != url else { return }
        load(url, autoplay: false)
        warming = true
        player.currentItem?.preferredForwardBufferDuration = 3
        prerollIfReady()
    }
    private func prerollIfReady() {
        guard warming, !wantsPlayback, player.rate == 0,
              player.status == .readyToPlay, player.currentItem?.status == .readyToPlay else { return }
        warming = false
        // Silent, bounded next-video warmup; never calls play or consumes an allowance.
        player.preroll(atRate: 1) { _ in }
    }
    func play() {
        guard error == nil, player.currentItem != nil else { return }
        if !wantsPlayback { wantsPlayback = true }
        warming = false
        player.cancelPendingPrerolls()
        player.currentItem?.preferredForwardBufferDuration = 0
        guard player.currentItem?.status == .readyToPlay, !seeking else {
            updatePlaybackState()
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            if audio.category != .playback || audio.mode != .moviePlayback {
                try audio.setCategory(.playback, mode: .moviePlayback)
            }
            try audio.setActive(true)
        } catch { fail("Audio playback is unavailable."); return }
        // Unlike playImmediately, this respects automaticallyWaitsToMinimizeStalling.
        player.rate = speed
        updatePlaybackState()
    }
    func pause() {
        if wantsPlayback { wantsPlayback = false }
        warming = false
        player.cancelPendingPrerolls()
        player.pause()
        player.currentItem?.preferredForwardBufferDuration = 3
        updatePlaybackState()
    }
    func toggle() { wantsPlayback ? pause() : play() }
    func setMuted(_ value: Bool) { muted = value; player.isMuted = value }
    func setSpeed(_ value: Float) {
        guard value.isFinite, value > 0 else { return }
        speed = value
        if wantsPlayback { play() }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite, player.currentItem != nil else { return }
        let length = player.currentItem?.duration.seconds ?? 0
        pendingSeek = max(0, length.isFinite && length > 0 ? min(seconds, length) : seconds)
        player.pause()
        player.cancelPendingPrerolls()
        performPendingSeek()
    }
    private func performPendingSeek() {
        guard !seeking, player.currentItem?.status == .readyToPlay, let target = pendingSeek else { return }
        pendingSeek = nil
        seeking = true
        let token = generation
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.seeking = false
                if self.pendingSeek != nil { self.performPendingSeek() }
                else {
                    if finished { self.timeline.elapsed = target }
                    if self.wantsPlayback { self.play() }
                }
            }
        }
    }
    private func updatePlaybackState() {
        let playing = error == nil && wantsPlayback && player.timeControlStatus == .playing
        let loading = error == nil && player.currentItem != nil &&
            (player.currentItem?.status == .unknown || (wantsPlayback && player.timeControlStatus == .waitingToPlayAtSpecifiedRate))
        if isPlaying != playing { isPlaying = playing }
        if isLoading != loading { isLoading = loading }
        if loading, wantsPlayback, loadingDeadline == nil {
            let token = generation
            loadingDeadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard let self, self.generation == token, self.wantsPlayback, self.isLoading else { return }
                self.fail("This video is taking too long to load. Check your connection and retry.")
            }
        } else if !loading || !wantsPlayback {
            loadingDeadline?.cancel()
            loadingDeadline = nil
        }
    }
    private func fail(_ message: String) {
        pause()
        error = message
        isLoading = false
    }
    func release() {
        generation = UUID()
        pause()
        status = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
        pendingSeek = nil
        seeking = false
        player.currentItem?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        loadedURL = nil
        timeline.elapsed = 0
        timeline.duration = 0
        isLoading = false
    }
    deinit {
        loadingDeadline?.cancel()
        if let timer { player.removeTimeObserver(timer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }
}

// Screen-owned: current, previous and next only. No disk download/cache or quota writes.
@MainActor
final class PlaybackPool: ObservableObject {
    @Published private(set) var controllers: [String: PlaybackController] = [:]
    private var selectedID: String?
    private var nextEntry: PlaybackQueueEntry?
    private var warmupTask: Task<Void, Never>?
    private var warmupID: String?

    func update(clips: [LessonClip], selectedID: String?) {
        update(entries: clips.map { PlaybackQueueEntry(id: $0.id, clip: $0) }, selectedID: selectedID)
    }
    func update(entries: [PlaybackQueueEntry], selectedID: String?) {
        guard let selectedID, let index = entries.firstIndex(where: { $0.id == selectedID }) else {
            releaseAll()
            return
        }
        if self.selectedID != selectedID { cancelWarmup() }
        self.selectedID = selectedID
        nextEntry = entries.indices.contains(index + 1) ? entries[index + 1] : nil
        let nearby = entries[max(0, index - 1)...min(entries.count - 1, index + 1)]
        let ids = Set(nearby.map(\.id))
        for (id, controller) in controllers {
            if !ids.contains(id) { controller.release() }
            else if id != selectedID, controller.intendsPlayback { controller.pause() }
        }
        var retained: [String: PlaybackController] = [:]
        for entry in nearby {
            let controller = controllers[entry.id] ?? PlaybackController()
            if let url = controller.loadedURL, url != entry.clip.playbackURL { controller.release() }
            retained[entry.id] = controller
        }
        guard let current = retained[selectedID] else { return }
        if current.loadedURL == nil { current.load(entries[index].clip.playbackURL, autoplay: false) }
        // Appending a feed batch should not invalidate every visible video page.
        if controllers.count != retained.count || retained.contains(where: { controllers[$0.key] !== $0.value }) {
            controllers = retained
        }
        if current.isPlaying { prepareNext(after: selectedID) }
    }
    func prepareNext(after id: String) {
        guard id == selectedID, controllers[id]?.isPlaying == true,
              let nextEntry, let upcoming = controllers[nextEntry.id],
              upcoming.loadedURL != nextEntry.clip.playbackURL else { return }
        guard warmupID != nextEntry.id else { return }
        cancelWarmup()
        warmupID = nextEntry.id
        warmupTask = Task { [weak self] in
            // Let the current stream establish its buffer before competing for bandwidth.
            // These thresholds are app policy, not guarantees from AVFoundation.
            for _ in 0..<24 {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, self.selectedID == id, self.nextEntry?.id == nextEntry.id,
                      let current = self.controllers[id], current.isPlaying else { return }
                guard let item = current.player.currentItem else { return }
                let position = current.player.currentTime().seconds
                let duration = item.duration.seconds
                let ahead = item.loadedTimeRanges.reduce(0.0) { longest, value in
                    let range = value.timeRangeValue
                    let start = range.start.seconds
                    let end = CMTimeRangeGetEnd(range).seconds
                    guard start.isFinite, end.isFinite, position >= start, position <= end else { return longest }
                    return max(longest, end - position)
                }
                let remaining = duration.isFinite ? max(0, duration - position) : 4
                guard position.isFinite, item.isPlaybackLikelyToKeepUp,
                      ahead >= min(4, remaining) else { continue }
                self.controllers[nextEntry.id]?.prepare(nextEntry.clip.playbackURL)
                return
            }
        }
    }
    private func cancelWarmup() {
        warmupTask?.cancel()
        warmupTask = nil
        warmupID = nil
    }
    func suspend() {
        cancelWarmup()
        // The active page records its resume intent before pausing itself.
        for (id, controller) in controllers where id != selectedID { controller.pause() }
    }
    func trimMemory() {
        cancelWarmup()
        for (id, controller) in controllers where id != selectedID { controller.release() }
        controllers = controllers.filter { $0.key == selectedID }
    }
    func releaseAll() {
        cancelWarmup()
        controllers.values.forEach { $0.release() }
        controllers = [:]
        selectedID = nil
        nextEntry = nil
    }
    deinit { warmupTask?.cancel() }
}

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var fill = true
    var onReadyForDisplay: ((Bool) -> Void)?
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        let coordinator = context.coordinator
        coordinator.onReadyForDisplay = onReadyForDisplay
        coordinator.observation = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak coordinator] layer, _ in
            Task { @MainActor [weak coordinator, weak layer] in
                guard let layer else { return }
                coordinator?.onReadyForDisplay?(layer.isReadyForDisplay)
            }
        }
        return view
    }
    func updateUIView(_ view: PlayerLayerView, context: Context) {
        context.coordinator.onReadyForDisplay = onReadyForDisplay
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        let gravity: AVLayerVideoGravity = fill ? .resizeAspectFill : .resizeAspect
        if view.playerLayer.videoGravity != gravity { view.playerLayer.videoGravity = gravity }
    }
    static func dismantleUIView(_ view: PlayerLayerView, coordinator: Coordinator) {
        coordinator.observation = nil
        coordinator.onReadyForDisplay = nil
        view.playerLayer.player = nil
    }
    final class Coordinator {
        var observation: NSKeyValueObservation?
        var onReadyForDisplay: ((Bool) -> Void)?
    }
}
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
func durationLabel(_ seconds: Double) -> String {
    let safe = seconds.isFinite ? max(0, seconds) : 0
    let number = Int(min(safe, 359999))
    return String(format: "%d:%02d", number / 60, number % 60)
}

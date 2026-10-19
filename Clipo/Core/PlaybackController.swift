import AVFoundation
import SwiftUI

@MainActor
final class PlaybackController: ObservableObject {
    let player = AVPlayer()
    @Published var isPlaying = false
    @Published var isLoading = true
    @Published var error: String?
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var muted = false
    @Published var speed: Float = 1
    private var status: NSKeyValueObservation?
    private var timeStatus: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var timer: Any?
    private var wantsPlayback = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsed = time.seconds.isFinite ? time.seconds : 0
                let seconds = self.player.currentItem?.duration.seconds ?? 0
                self.duration = seconds.isFinite ? max(0, seconds) : 0
            }
        }
        timeStatus = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = player.timeControlStatus == .playing
                self.isLoading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate || player.currentItem?.status == .unknown
            }
        }
    }
    func load(_ url: URL, autoplay: Bool) { load(AVPlayerItem(url: url), autoplay: autoplay) }
    func load(_ item: AVPlayerItem, autoplay: Bool) {
        pause()
        status = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        error = nil
        elapsed = 0
        duration = 0
        isLoading = true
        wantsPlayback = autoplay
        player.replaceCurrentItem(with: item)
        status = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === observed else { return }
                if observed.status == .failed {
                    self.error = observed.error?.localizedDescription ?? "This clip could not be played."
                    self.isLoading = false
                } else if observed.status == .readyToPlay {
                    self.isLoading = false
                    if self.wantsPlayback { self.play() }
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player.seek(to: .zero)
                if self.wantsPlayback { self.play() }
            }
        }
    }
    func play() {
        wantsPlayback = true
        guard error == nil else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { self.error = "Audio playback is unavailable."; return }
        player.playImmediately(atRate: speed)
    }
    func pause() { wantsPlayback = false; player.pause(); isPlaying = false }
    func toggle() { isPlaying ? pause() : play() }
    func setMuted(_ value: Bool) { muted = value; player.isMuted = value }
    func setSpeed(_ value: Float) { speed = value; if isPlaying { player.rate = value } }
    func seek(_ seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600))
    }
    func release() { pause(); player.replaceCurrentItem(with: nil) }
    deinit {
        if let timer { player.removeTimeObserver(timer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var fill = true
    func makeUIView(context: Context) -> PlayerLayerView { PlayerLayerView() }
    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
    static func dismantleUIView(_ view: PlayerLayerView, coordinator: ()) { view.playerLayer.player = nil }
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

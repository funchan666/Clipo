import AVFoundation
import SwiftUI

enum ExportQuality: String, CaseIterable, Identifiable {
    case full = "1080p", compact = "720p", small = "480p"
    var id: String { rawValue }
    var edge: CGFloat { self == .full ? 1920 : self == .compact ? 1280 : 854 }
    var shortEdge: CGFloat { self == .full ? 1080 : self == .compact ? 720 : 480 }
}
enum VideoFrame: String, CaseIterable, Identifiable {
    case original = "Original", portrait = "9:16", square = "1:1", landscape = "16:9"
    var id: String { rawValue }
    var ratio: CGFloat? { self == .original ? nil : self == .portrait ? 9 / 16 : self == .square ? 1 : 16 / 9 }
}
struct EditRecipe: Equatable {
    var start: Double = 0
    var end: Double = 0
    var speed: Double = 1
    var quarterTurns: Int = 0
    var mirrored = false
    var muted = false
    var frame: VideoFrame = .original
    var quality: ExportQuality = .full
}

@MainActor
final class VideoEditor: ObservableObject {
    @Published var recipe = EditRecipe()
    @Published private(set) var duration: Double = 0
    @Published private(set) var thumbnails: [UIImage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isExporting = false
    @Published private(set) var progress: Float = 0
    @Published var error: String?
    @Published var exportedURL: URL?
    let preview = PlaybackController()
    private var sourceURL: URL?
    private var exporter: AVAssetExportSession?
    private var revision = UUID()
    private var cancelRequested = false

    func open(_ url: URL) async {
        let requestID = UUID()
        revision = requestID
        sourceURL = url
        duration = 0
        recipe = EditRecipe()
        error = nil
        isLoading = true
        exportedURL = nil
        thumbnails = []
        preview.release()
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let playable = try await asset.load(.isPlayable)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard playable, duration.isFinite, duration > 0.1, !tracks.isEmpty else { throw ClipoError.unsupportedMedia }
            guard revision == requestID else { return }
            self.duration = duration
            recipe = EditRecipe(start: 0, end: duration)
            preview.load(url, autoplay: false)
            isLoading = false
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 180, height: 180)
            for step in 0..<7 {
                try Task.checkCancellation()
                let time = CMTime(seconds: duration * Double(step) / 7, preferredTimescale: 600)
                if let result = try? await generator.image(at: time) {
                    guard revision == requestID else { return }
                    thumbnails.append(UIImage(cgImage: result.image))
                }
            }
        } catch {
            guard revision == requestID else { return }
            self.error = error.localizedDescription
            sourceURL = nil
            isLoading = false
        }
    }

    func applyPreview() async {
        guard let sourceURL, !isExporting else { return }
        let requestedRecipe = recipe
        let requestID = revision
        do {
            let (composition, video) = try await compose(url: sourceURL, recipe: requestedRecipe)
            guard requestID == revision, recipe == requestedRecipe else { return }
            preview.pause()
            let item = AVPlayerItem(asset: composition)
            item.videoComposition = video
            preview.setMuted(false)
            preview.setSpeed(1)
            preview.load(item, autoplay: true)
        } catch { self.error = error.localizedDescription }
    }

    func export(audioOnly: Bool = false) async -> URL? {
        guard let sourceURL, !isExporting else { return nil }
        isExporting = true
        cancelRequested = false
        progress = 0
        error = nil
        preview.pause()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Clipo-\(UUID().uuidString).\(audioOnly ? "m4a" : "mp4")")
        defer { isExporting = false; exporter = nil }
        var progressTask: Task<Void, Never>?
        defer { progressTask?.cancel() }
        do {
            let (composition, video) = try await compose(url: sourceURL, recipe: recipe)
            try Task.checkCancellation()
            if cancelRequested { throw CancellationError() }
            if audioOnly, composition.tracks(withMediaType: .audio).isEmpty {
                throw ClipoError.service("This clip has no audio. Turn off Mute if you want to extract its soundtrack.")
            }
            guard let session = AVAssetExportSession(asset: composition, presetName: audioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality) else { throw ClipoError.unsupportedMedia }
            exporter = session
            session.outputURL = output
            session.outputFileType = audioOnly ? .m4a : .mp4
            if !audioOnly { session.videoComposition = video }
            session.shouldOptimizeForNetworkUse = true
            progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.progress = session.progress
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    session.exportAsynchronously { continuation.resume() }
                }
            } onCancel: { session.cancelExport() }
            switch session.status {
            case .completed:
                guard FileManager.default.fileExists(atPath: output.path),
                      (try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else { throw ClipoError.storage }
                progress = 1
                exportedURL = output
                return output
            case .cancelled: throw CancellationError()
            default: throw session.error ?? ClipoError.service("Export could not finish. Your original video is unchanged.")
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            self.error = error is CancellationError ? "Export cancelled. Your original video is unchanged." : error.localizedDescription
            return nil
        }
    }
    func cancelExport() { cancelRequested = true; exporter?.cancelExport() }
    func close() { revision = UUID(); preview.release(); cancelExport() }

    private func compose(url: URL, recipe: EditRecipe) async throws -> (AVMutableComposition, AVMutableVideoComposition) {
        let source = AVURLAsset(url: url)
        guard let videoSource = try await source.loadTracks(withMediaType: .video).first else { throw ClipoError.unsupportedMedia }
        let sourceDuration = try await source.load(.duration).seconds
        let start = max(0, min(recipe.start, sourceDuration - 0.1))
        let end = max(start + 0.1, min(recipe.end, sourceDuration))
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: end - start, preferredTimescale: 600))
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ClipoError.unsupportedMedia }
        try track.insertTimeRange(range, of: videoSource, at: .zero)
        if !recipe.muted {
            for audioSource in try await source.loadTracks(withMediaType: .audio) {
                guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                let audioRange = try await audioSource.load(.timeRange)
                let overlap = CMTimeRangeGetIntersection(range, audioRange)
                if overlap.duration.seconds > 0 {
                    try audio.insertTimeRange(overlap, of: audioSource, at: CMTimeSubtract(overlap.start, range.start))
                }
            }
        }
        let speed = max(0.25, min(recipe.speed, 4))
        composition.scaleTimeRange(CMTimeRange(start: .zero, duration: range.duration),
                                   toDuration: CMTime(seconds: (end - start) / speed, preferredTimescale: 600))
        let naturalSize = try await videoSource.load(.naturalSize)
        var transform = try await videoSource.load(.preferredTransform)
        transform = transform.concatenating(CGAffineTransform(rotationAngle: CGFloat(recipe.quarterTurns % 4) * .pi / 2))
        if recipe.mirrored { transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: 1)) }
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        guard bounds.width > 0, bounds.height > 0 else { throw ClipoError.unsupportedMedia }
        transform = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        var crop = bounds.size
        if let ratio = recipe.frame.ratio {
            if crop.width / crop.height > ratio { crop.width = crop.height * ratio }
            else { crop.height = crop.width / ratio }
        }
        transform = transform.concatenating(CGAffineTransform(translationX: -(bounds.width - crop.width) / 2, y: -(bounds.height - crop.height) / 2))
        let scale = min(1, min(recipe.quality.edge / max(crop.width, crop.height),
                               recipe.quality.shortEdge / min(crop.width, crop.height)))
        let render = CGSize(width: max(2, floor(crop.width * scale / 2) * 2), height: max(2, floor(crop.height * scale / 2) * 2))
        transform = transform.concatenating(CGAffineTransform(scaleX: render.width / crop.width, y: render.height / crop.height))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = [layer]
        let video = AVMutableVideoComposition()
        video.renderSize = render
        video.frameDuration = CMTime(value: 1, timescale: 30)
        video.instructions = [instruction]
        return (composition, video)
    }
}

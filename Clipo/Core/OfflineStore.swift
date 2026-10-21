import Foundation
import AVFoundation
import Combine

struct OfflineVideo: Codable, Identifiable {
    let clip: LessonClip
    let relativePath: String
    let isHLS: Bool
    let owner: String
    var id: String { clip.id }
    var url: URL { URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(relativePath) }
}

private struct OfflineTransfer: Codable {
    let id: UUID
    let clip: LessonClip
    let owner: String
    let premium: Bool
    let isHLS: Bool
    var relativePath: String?
    var completed = false
}
private struct OfflineIndex: Codable {
    var videos: [OfflineVideo] = []
    var transfer: OfflineTransfer?
}

// One admitted download at a time, independent of streaming/preloading and favorites.
// The persisted transfer is a completion journal: file -> quota -> visible library.
@MainActor
final class OfflineStore: NSObject, ObservableObject {
    @Published private(set) var videos: [OfflineVideo] = []
    @Published private(set) var downloadingID: String?
    @Published private(set) var progress = 0.0
    @Published var error: String?
    private let api: APIClient
    private let quota: QuotaStore
    private let commerce: CommerceStore
    private let root: URL
    private let indexURL: URL
    private var index = OfflineIndex()
    private var readable = true
    private var restored = false
    private var finalizing = false
    @Published private(set) var preparingID: String?
    @Published private var restoring = false
    private var progressObservation: NSKeyValueObservation?
    private lazy var hlsSession: AVAssetDownloadURLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: api.configuration.bundleID + ".offline.hls")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = false
        return AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: self, delegateQueue: .main)
    }()
    private lazy var fileSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: api.configuration.bundleID + ".offline.files")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = false
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    var busy: Bool { restoring || preparingID != nil || downloadingID != nil }
    var isRestoring: Bool { restoring }
    var currentTitle: String? { index.transfer?.clip.title }

    init(api: APIClient, quota: QuotaStore, commerce: CommerceStore) {
        self.api = api; self.quota = quota; self.commerce = commerce
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipoOffline", isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")
        super.init()
        do {
            var directory = root
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                index = try JSONDecoder().decode(OfflineIndex.self, from: Data(contentsOf: indexURL))
            }
            publish()
        } catch { readable = false; self.error = "Offline downloads could not be read. Existing files have been preserved." }
    }
    func cached(_ id: String) -> OfflineVideo? {
        videos.first { $0.id == id && $0.owner == api.session?.userId.value && FileManager.default.fileExists(atPath: $0.url.path) }
    }
    func playable(_ clip: LessonClip) -> LessonClip {
        guard let video = cached(clip.id) else { return clip }
        return LessonClip(id: clip.id, title: clip.title, playbackURL: video.url, coverURL: clip.coverURL,
                    shortLink: clip.shortLink, channel: clip.channel, duration: clip.duration)
    }
    func resumePending() async {
        guard readable, !restored, api.session != nil else { return }
        restored = true
        restoring = true
        defer { restoring = false }
        publish() // The index was initially read before guest authentication finished.
        let hlsTasks = await hlsSession.allTasks
        let fileTasks = await fileSession.allTasks
        let tasks = hlsTasks + fileTasks
        guard let transfer = index.transfer else { tasks.forEach { $0.cancel() }; return }
        let matching = tasks.filter { $0.taskDescription == transfer.id.uuidString }
        tasks.filter { $0.taskDescription != transfer.id.uuidString }.forEach { $0.cancel() }
        guard transfer.owner == api.session?.userId.value else {
            matching.forEach { $0.cancel() }; fail(transfer.id, message: "Download interrupted. Please try again."); return
        }
        if transfer.completed {
            if transfer.relativePath == nil, matching.isEmpty {
                fail(transfer.id, message: "Download interrupted. Please try again.")
            } else { await finishIfReady() }
        }
        else if matching.isEmpty { fail(transfer.id, message: "Download interrupted. Please try again.") }
        else {
            matching.forEach { observeProgress(of: $0, transferID: transfer.id); $0.resume() }
        }
    }
    func download(_ clip: LessonClip) async {
        guard preparingID == nil else { error = "Another download is being prepared."; return }
        preparingID = clip.id
        defer { preparingID = nil }
        error = nil
        await resumePending()
        guard readable else { error = "Offline downloads could not be read. Existing files have been preserved."; return }
        guard !restoring, downloadingID == nil else { error = "Another download is in progress."; return }
        if cached(clip.id) != nil { return }
        guard let owner = api.session?.userId.value else { error = "Connect to your account before downloading."; return }
        guard !clip.playbackURL.isFileURL else { error = "This video is already stored on this device."; return }
        guard quota.mayDownload(clip.id, premium: commerce.premium) else {
            error = "Your download allowance is used up."; return
        }
        // Expired/missing local files may be re-downloaded. QuotaStore remembers paid IDs.
        let isHLS: Bool
        do { isHLS = try await isHLSMedia(at: clip.playbackURL) }
        catch is CancellationError { return }
        catch { self.error = "Download could not start. Please check your connection."; return }
        guard owner == api.session?.userId.value else { error = "Connect to your account before downloading."; return }
        guard quota.mayDownload(clip.id, premium: commerce.premium) else { error = "Your download allowance is used up."; return }
        let transfer = OfflineTransfer(id: UUID(), clip: clip, owner: owner, premium: commerce.premium, isHLS: isHLS)
        do {
            var next = index; next.transfer = transfer
            try persist(next)
            progress = 0
            let task: URLSessionTask
            if isHLS {
                let configuration = AVAssetDownloadConfiguration(asset: AVURLAsset(url: clip.playbackURL), title: clip.title)
                task = hlsSession.makeAssetDownloadTask(downloadConfiguration: configuration)
            } else {
                task = fileSession.downloadTask(with: clip.playbackURL)
            }
            task.taskDescription = transfer.id.uuidString
            observeProgress(of: task, transferID: transfer.id)
            task.resume()
        } catch { self.error = error.localizedDescription }
    }
    private func isHLSMedia(at url: URL) async throws -> Bool {
        let extensionName = url.pathExtension.lowercased()
        if extensionName == "m3u8" { return true }
        if ["mp4", "mov", "m4v"].contains(extensionName) { return false }
        // Signed/extensionless sources may reject HEAD. Probe only a small GET
        // prefix, then cancel the session even when the server ignores Range.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("bytes=0-511", forHTTPHeaderField: "Range")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw ClipoError.invalidResponse
        }
        if response.mimeType?.lowercased().contains("mpegurl") == true || response.url?.pathExtension.lowercased() == "m3u8" { return true }
        var prefix = Data()
        for try await byte in bytes {
            prefix.append(byte)
            if prefix.count >= 512 { break }
        }
        return String(decoding: prefix, as: UTF8.self).contains("#EXTM3U")
    }
    private func observeProgress(of task: URLSessionTask, transferID: UUID) {
        progressObservation = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            let value = progress.fractionCompleted
            Task { @MainActor [weak self] in self?.updateProgress(id: transferID, value: value) }
        }
    }
    func cancel() async {
        guard let transfer = index.transfer, !finalizing else { return }
        let hlsTasks = await hlsSession.allTasks
        let fileTasks = await fileSession.allTasks
        let tasks = hlsTasks + fileTasks
        tasks.filter { $0.taskDescription == transfer.id.uuidString }.forEach { $0.cancel() }
        fail(transfer.id, message: nil)
    }
    func remove(_ video: OfflineVideo) {
        do {
            var next = index; next.videos.removeAll { $0.id == video.id }
            try persist(next)
            try? FileManager.default.removeItem(at: video.url)
        } catch { self.error = error.localizedDescription }
    }
    private func receiveLocation(id: UUID, url: URL) {
        guard var transfer = index.transfer, transfer.id == id else {
            let resolved = url.resolvingSymlinksInPath()
            if !index.videos.contains(where: { $0.url.resolvingSymlinksInPath() == resolved }) {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }
        let prefix = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/"
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(prefix) else { fail(id, message: "Download could not be saved."); return }
        transfer.relativePath = String(path.dropFirst(prefix.count))
        do {
            var next = index; next.transfer = transfer
            try persist(next)
            Task { await finishIfReady() }
        } catch {
            // Keep the location in memory if disk space prevents journaling; Retry
            // persists it before charging. A process loss may orphan a file, not a charge.
            index.transfer = transfer
            publish()
            self.error = "Download is waiting to be saved. Tap Retry."
        }
    }
    private func completed(id: UUID, failure: Error?) {
        guard var transfer = index.transfer, transfer.id == id else { return }
        if let failure {
            fail(id, message: (failure as NSError).code == NSURLErrorCancelled ? nil : "Download failed. No download allowance was used.")
            return
        }
        transfer.completed = true
        do {
            var next = index; next.transfer = transfer
            try persist(next)
            Task { await finishIfReady() }
        } catch {
            index.transfer = transfer
            publish()
            self.error = "Download is waiting to be saved. Tap Retry."
        }
    }
    private func finishIfReady() async {
        guard !finalizing, let transfer = index.transfer, transfer.completed,
              let path = transfer.relativePath else { return }
        finalizing = true
        defer { finalizing = false }
        let video = OfflineVideo(clip: transfer.clip, relativePath: path, isHLS: transfer.isHLS, owner: transfer.owner)
        do {
            guard FileManager.default.fileExists(atPath: video.url.path) else { throw ClipoError.storage }
            let asset = AVURLAsset(url: video.url)
            let playable = try await asset.load(.isPlayable)
            guard playable, !transfer.isHLS || asset.assetCache?.isPlayableOffline == true else {
                fail(transfer.id, message: "This video is not available for offline playback."); return
            }
        } catch {
            fail(transfer.id, message: "This video is not available for offline playback.")
            return
        }
        do {
            guard index.transfer?.id == transfer.id, transfer.owner == api.session?.userId.value else { return }
            try quota.recordDownload(video.id, owner: transfer.owner, premium: transfer.premium || commerce.premium)
            var next = index
            next.videos.removeAll { $0.id == video.id }
            next.videos.insert(video, at: 0)
            next.transfer = nil
            try persist(next)
            progressObservation = nil
            progress = 1
        } catch {
            // Keep completed file + journal; retry can finish the quota/index commit
            // idempotently without starting another transfer or charging twice.
            self.error = "Download is waiting to be saved. Tap Retry."
        }
    }
    func retryCompletion() async {
        do {
            try persist(index)
            error = nil
            await finishIfReady()
        } catch { self.error = "Download is waiting to be saved. Tap Retry." }
    }
    private func fail(_ id: UUID, message: String?) {
        guard let transfer = index.transfer, transfer.id == id else { return }
        do {
            var next = index; next.transfer = nil
            try persist(next)
            progressObservation = nil
            if let path = transfer.relativePath {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(path))
            }
            error = message
        } catch { self.error = error.localizedDescription }
    }
    private func persist(_ value: OfflineIndex) throws {
        guard readable else { throw ClipoError.storage }
        try JSONEncoder().encode(value).write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        index = value
        publish()
    }
    private func publish() {
        videos = index.videos.filter { $0.owner == api.session?.userId.value }
        downloadingID = index.transfer?.clip.id
    }
    private func updateProgress(id: UUID, value: Double) {
        guard index.transfer?.id == id, value.isFinite else { return }
        progress = min(1, max(0, value))
    }
}

extension OfflineStore: AVAssetDownloadDelegate, URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        Task { @MainActor in self.receiveLocation(id: id, url: location) }
    }
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        guard let id = assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        Task { @MainActor in self.receiveLocation(id: id, url: location) }
    }
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange,
                               totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        guard let id = assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        let duration = timeRangeExpectedToLoad.duration.seconds
        let loaded = loadedTimeRanges.reduce(0) { $0 + $1.timeRangeValue.duration.seconds }
        Task { @MainActor in self.updateProgress(id: id, value: duration > 0 ? loaded / duration : 0) }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            Task { @MainActor in self.fail(id, message: "Download failed. No download allowance was used.") }; return
        }
        // URLSession's temporary file must be moved before this delegate returns.
        do {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClipoOffline")
            let ext = downloadTask.originalRequest?.url?.pathExtension.lowercased() ?? ""
            let destination = root.appendingPathComponent(id.uuidString).appendingPathExtension(["mp4", "mov", "m4v"].contains(ext) ? ext : "mp4")
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in self.receiveLocation(id: id, url: destination) }
        } catch { Task { @MainActor in self.fail(id, message: "Download could not be saved.") } }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                               totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        Task { @MainActor in self.updateProgress(id: id, value: totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0) }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        Task { @MainActor in self.completed(id: id, failure: error) }
    }
}

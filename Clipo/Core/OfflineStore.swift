import Foundation
import AVFoundation
import Combine
import OSLog

// Persist paths within the app relative to its container: iOS can relocate it
// on an update. AVFoundation may prepend /.nofollow to its callback URL.
enum OfflineAssetLocation {
    static func canonical(_ url: URL) -> URL {
        let path = url.path
        let unwrapped = path.hasPrefix("/.nofollow/") ? String(path.dropFirst("/.nofollow".count)) : path
        return URL(fileURLWithPath: unwrapped).standardizedFileURL.resolvingSymlinksInPath()
    }
    static func relativePath(_ url: URL, home: URL) -> String? {
        let root = canonical(home).pathComponents
        let location = canonical(url).pathComponents
        guard location.count > root.count, Array(location.prefix(root.count)) == root else { return nil }
        return location.dropFirst(root.count).joined(separator: "/")
    }
    static func restoredHLSURL(_ stored: URL, home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        let original = canonical(stored)
        if FileManager.default.fileExists(atPath: original.path) { return original }
        // Migrate the old absolute AVFoundation location only when the same
        // system-managed package actually exists inside this app's new home.
        let parts = original.pathComponents
        guard original.pathExtension == "movpkg", let library = parts.lastIndex(of: "Library"),
              library >= 5, library + 2 == parts.count - 1,
              parts[library - 4] == "Containers", parts[library - 3] == "Data",
              parts[library - 2] == "Application", UUID(uuidString: parts[library - 1]) != nil,
              parts[library + 1].hasPrefix("com.apple.UserManagedAssets.") else { return stored }
        let relocated = home.appendingPathComponent(parts[library...].joined(separator: "/"))
        return FileManager.default.fileExists(atPath: relocated.path) ? relocated : stored
    }
}

struct OfflineVideo: Codable, Identifiable {
    let clip: LessonClip
    let relativePath: String
    let isHLS: Bool
    let owner: String
    // AVFoundation owns HLS storage. Its file URL need not be inside our home
    // directory. Older indexes only contain relativePath and remain readable.
    var systemAssetURL: URL? = nil
    var id: String { clip.id }
    var url: URL {
        if isHLS, let systemAssetURL, systemAssetURL.isFileURL { return OfflineAssetLocation.restoredHLSURL(systemAssetURL) }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(relativePath)
    }
}

private struct OfflineTransfer: Codable {
    let id: UUID
    let clip: LessonClip
    let owner: String
    let premium: Bool
    let isHLS: Bool
    var relativePath: String?
    var systemAssetURL: URL?
    var completed = false
    var forExport: Bool?
    var savedURL: URL? {
        if isHLS, let systemAssetURL, systemAssetURL.isFileURL { return OfflineAssetLocation.restoredHLSURL(systemAssetURL) }
        return relativePath.map { URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent($0) }
    }
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
    @Published var completedDownloadID: UUID?
    private var ownerObservation: AnyCancellable?
    private let api: APIClient
    private let quota: QuotaStore
    private let commerce: CommerceStore
    private nonisolated let root: URL
    private let indexURL: URL
    private var index = OfflineIndex()
    private var readable = true
    private var restored = false
    private var finalizing = false
    @Published private(set) var preparingID: String?
    @Published private var restoring = false
    private var progressObservation: NSKeyValueObservation?
    private var conversionTask: Task<Void, Never>?
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
        ownerObservation = api.$offlineOwnerID.removeDuplicates().sink { [weak self] owner in
            // Use the emitted value: @Published delivers before its property changes.
            self?.videos = self?.index.videos.filter { $0.owner == owner } ?? []
        }
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
        videos.first { $0.id == id && $0.owner == api.offlineOwnerID && FileManager.default.fileExists(atPath: $0.url.path) }
    }
    func playable(_ clip: LessonClip) -> LessonClip {
        guard let video = cached(clip.id) else { return clip }
        return LessonClip(id: clip.id, title: clip.title, playbackURL: video.url, coverURL: clip.coverURL,
                    shortLink: clip.shortLink, channel: clip.channel, duration: clip.duration,
                    exportSources: clip.exportSources ?? video.clip.exportSources)
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
            if transfer.savedURL == nil, matching.isEmpty {
                fail(transfer.id, message: "Download interrupted. Please try again.")
            } else { await finishIfReady() }
        }
        else if matching.isEmpty { fail(transfer.id, message: "Download interrupted. Please try again.") }
        else {
            matching.forEach { observeProgress(of: $0, transferID: transfer.id); $0.resume() }
        }
    }
    func download(_ clip: LessonClip, forExport: Bool = false) async {
        if forExport {
            do { try commerce.requireMediaExport() }
            catch { self.error = error.localizedDescription; return }
        }
        guard preparingID == nil else { error = "Another download is being prepared."; return }
        preparingID = clip.id
        defer { preparingID = nil }
        error = nil
        await resumePending()
        guard readable else { error = "Offline downloads could not be read. Existing files have been preserved."; return }
        guard !restoring, downloadingID == nil else { error = "Another download is in progress."; return }
        if let existing = cached(clip.id), !forExport || !existing.isHLS { return }
        guard let owner = api.session?.userId.value else { error = "Connect to your account before downloading."; return }
        guard forExport || !clip.playbackURL.isFileURL else { error = "This video is already stored on this device."; return }
        guard quota.mayDownload(clip.id, premium: commerce.premium) else {
            error = "Your download allowance is used up."; return
        }
        // Expired/missing local files may be re-downloaded. QuotaStore remembers paid IDs.
        let isHLS: Bool
        let source: URL
        do {
            source = forExport ? try await originalFileSource(for: clip) : clip.playbackURL
            isHLS = try await isHLSMedia(at: source)
            try Task.checkCancellation()
        }
        catch is CancellationError { return }
        catch { self.error = forExport ? error.localizedDescription : "Download could not start. Please check your connection."; return }
        guard owner == api.session?.userId.value else { error = "Connect to your account before downloading."; return }
        guard quota.mayDownload(clip.id, premium: commerce.premium) else { error = "Your download allowance is used up."; return }
        if forExport {
            do { try commerce.requireMediaExport() }
            catch { self.error = error.localizedDescription; return }
        }
        // A player may hand us its local playback copy. Keep the remote identity
        // in the index so a removed cache can still be downloaded/exported again.
        let originalClip = clip.playbackURL.isFileURL ? (cached(clip.id)?.clip ?? clip) : clip
        let transfer = OfflineTransfer(id: UUID(), clip: originalClip, owner: owner, premium: commerce.premium,
                                       isHLS: isHLS && !forExport, forExport: forExport)
        do {
            var next = index; next.transfer = transfer
            try persist(next)
            progress = 0
            if forExport, isHLS {
                let destination = root.appendingPathComponent(transfer.id.uuidString).appendingPathExtension("mp4")
                let task = Task { @MainActor in
                    do {
                        try await LessonStreamExport.Job().convert(source, destination: destination) { [weak self] value in
                            await self?.updateProgress(id: transfer.id, value: value)
                        }
                        try Task.checkCancellation()
                        guard self.index.transfer?.id == transfer.id else {
                            try? FileManager.default.removeItem(at: destination); return
                        }
                        self.receiveLocation(id: transfer.id, url: destination)
                        self.completed(id: transfer.id, failure: nil)
                    } catch {
                        try? FileManager.default.removeItem(at: destination)
                        self.fail(transfer.id, message: Task.isCancelled ? nil : error.localizedDescription)
                    }
                }
                conversionTask = task
                await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
                conversionTask = nil
                return
            }
            let task: URLSessionTask
            if isHLS {
                let configuration = AVAssetDownloadConfiguration(asset: AVURLAsset(url: source), title: clip.title)
                task = hlsSession.makeAssetDownloadTask(downloadConfiguration: configuration)
            } else {
                task = fileSession.downloadTask(with: source)
            }
            task.taskDescription = transfer.id.uuidString
            observeProgress(of: task, transferID: transfer.id)
            task.resume()
        } catch { self.error = error.localizedDescription }
    }
    static let missingExportSource = "The provider has not supplied a downloadable video file. You can still cache this video for offline viewing."

    private func originalFileSource(for clip: LessonClip) async throws -> URL {
        let original = cached(clip.id)?.clip ?? clip
        var candidates = (clip.exportSources ?? []) + (original.exportSources ?? [])
        if !original.playbackURL.isFileURL { candidates.append(original.playbackURL) }
        var checked = Set<URL>()
        var streamSource: URL?
        var lastFailure: Error?
        func selectFile(_ urls: [URL]) async throws -> URL? {
            for url in urls where checked.insert(url).inserted && !url.isFileURL {
                do {
                    if try await isHLSMedia(at: url) == false { return url }
                    if streamSource == nil { streamSource = url }
                } catch {
                    try Task.checkCancellation()
                    lastFailure = error
                }
            }
            return nil
        }
        if let url = try await selectFile(candidates) { return url }
        // The backend may only supply HLS. Repackage the actual stream on the
        // client rather than requiring an unavailable MP4 URL from the service.
        if let streamSource { return streamSource }
        // Resolve only this video's short link. A folder or a different video
        // must never be exported under the currently playing video's title.
        if let link = (clip.shortLink ?? original.shortLink).flatMap({ WebAddress.landingCode($0) }) {
            do {
                let info = try await api.resolve(link, password: "")
                if let file = info.netDiskInfo, file.isFolder != true,
                   (file.id?.value == original.id ||
                    (file.id == nil && file.landingPage.flatMap({ WebAddress.landingCode($0) }) == link)) {
                    if let url = try await selectFile([file.fileUrl, file.originUrl].compactMap { WebAddress.media($0) }) {
                        return url
                    }
                }
            } catch {
                try Task.checkCancellation()
                lastFailure = error
            }
        }
        try Task.checkCancellation()
        if let streamSource { return streamSource }
        if let lastFailure { throw lastFailure }
        throw ClipoError.service(Self.missingExportSource)
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
        conversionTask?.cancel()
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
    private func receiveLocation(id: UUID, url: URL, systemManaged: Bool = false) {
        guard var transfer = index.transfer, transfer.id == id else {
            // A late HLS callback may arrive while AVFoundation is still writing.
            // Never remove its package in a willDownloadTo callback.
            guard !systemManaged else { return }
            let resolved = url.resolvingSymlinksInPath()
            if !index.videos.contains(where: { $0.url.resolvingSymlinksInPath() == resolved }) {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }
        guard url.isFileURL, transfer.isHLS == systemManaged else {
            fail(id, message: "Download location is unavailable. Please try again."); return
        }
        // Ordinary downloads belong to our container. HLS locations come only
        // from AVAssetDownloadDelegate, and must be retained wherever the OS put
        // them. Do not apply an application-container restriction to those URLs.
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        if let relative = OfflineAssetLocation.relativePath(url, home: home) {
            transfer.relativePath = relative
            transfer.systemAssetURL = nil
        } else if systemManaged {
            transfer.systemAssetURL = url.absoluteURL
            transfer.relativePath = nil
        } else {
            Logger(subsystem: "com.clipo.video", category: "Offline").error("Rejected offline location outside application container")
            fail(id, message: "Download location is unavailable. Please try again."); return
        }
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
              transfer.savedURL != nil else { return }
        finalizing = true
        defer { finalizing = false }
        let video = OfflineVideo(clip: transfer.clip, relativePath: transfer.relativePath ?? "",
                                 isHLS: transfer.isHLS, owner: transfer.owner, systemAssetURL: transfer.systemAssetURL)
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
            if transfer.forExport != true { completedDownloadID = UUID() }
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
            if let url = transfer.savedURL {
                try? FileManager.default.removeItem(at: url)
            } else if !transfer.isHLS {
                // Also clean a converter output left by termination before its
                // completion callback could journal the finished file location.
                try? FileManager.default.removeItem(at: root.appendingPathComponent(transfer.id.uuidString).appendingPathExtension("mp4"))
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
        videos = index.videos.filter { $0.owner == api.offlineOwnerID }
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
        Task { @MainActor in self.receiveLocation(id: id, url: location, systemManaged: true) }
    }
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        guard let id = assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        Task { @MainActor in self.receiveLocation(id: id, url: location, systemManaged: true) }
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
            // Use the same directory as the durable journal. Recreate it if the
            // system or a prior interrupted transfer removed the directory.
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let ext = downloadTask.originalRequest?.url?.pathExtension.lowercased() ?? ""
            let destination = root.appendingPathComponent(id.uuidString).appendingPathExtension(["mp4", "mov", "m4v"].contains(ext) ? ext : "mp4")
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in self.receiveLocation(id: id, url: destination) }
        } catch {
            let failure = error as NSError
            Logger(subsystem: "com.clipo.video", category: "Offline")
                .error("Offline file move failed: \(failure.domain, privacy: .public) code \(failure.code)")
            let message = failure.domain == NSCocoaErrorDomain && failure.code == NSFileWriteOutOfSpaceError
                ? "Not enough storage. Free up space and try again."
                : "Download could not be saved. Please try again. (\(failure.code))"
            Task { @MainActor in self.fail(id, message: message) }
        }
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

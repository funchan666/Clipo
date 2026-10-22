import SwiftUI
import AVFoundation

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingExportMembership = false
    var edit: (PracticeRecording) -> Void
    @Binding var filter: String
    @State private var player: PlayerRoute?
    @State private var sharing: SharedFile?
    @State private var removing: PracticeRecording?
    @State private var removingDownload: OfflineVideo?
    @State private var sharingMovieID: UUID?
    private var itemCount: Int {
        if filter == "Downloads" { return offline.videos.count }
        return filter == "Saved" ? library.favorites.count : library.movies.filter { $0.isExport == (filter == "Exports") }.count
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    TennisArtwork(kind: .notebook, height: min(geometry.size.width * 0.60, 260))
                        .padding(.top, geometry.safeAreaInsets.top + 12)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                        .background(ClipoStyle.background)
                    libraryContent
                }
            }.ignoresSafeArea(.container, edges: .top)
        }.clipoScreenBackground().sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
            .sheet(isPresented: $showingExportMembership) { MembershipView(exportRequired: true) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
            .sheet(item: $removingDownload) { video in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SheetHeading(title: "Remove offline video?") { removingDownload = nil }
                        Text(verbatim: video.clip.title).font(.court(.headline)).lineLimit(3)
                        LocalizedText("This removes only the offline copy. Your favorite stays saved.")
                            .foregroundStyle(ClipoStyle.secondary)
                        ActionButton(title: "Remove download", primary: false) {
                            offline.remove(video); removingDownload = nil
                        }
                        ActionButton(title: "Keep it") { removingDownload = nil }
                    }.padding(24)
                }.clipoScreenBackground().presentationDetents([.medium, .large])
            }
            .sheet(item: $removing) { movie in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SheetHeading(title: "Delete this local copy?") { removing = nil }
                        Text(verbatim: movie.title).font(.court(.headline))
                        LocalizedText("The copy in Clipo will be removed. The original in Photos or Files will stay untouched.").foregroundStyle(ClipoStyle.secondary)
                        ActionButton(title: "Delete local copy") { library.delete(movie); removing = nil }
                        ActionButton(title: "Keep it", primary: false) { removing = nil }
                    }.padding(24)
                }.clipoScreenBackground().presentationDetents([.medium, .large])
            }
    }
    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            libraryFilters
            if filter == "Downloads" { DownloadAllowanceSummary() }
            SectionLabel(title: categoryTitle(filter), detail: "\(itemCount) \(itemCount == 1 ? "item" : "items") · On this device")
            if offline.downloadingID != nil {
                if let title = offline.currentTitle { Text(verbatim: title).font(.court(.subheadline)).lineLimit(2) }
                LocalizedText("Downloading · \(Int(offline.progress * 100))%").font(.court(.caption))
                ActionButton(title: "Cancel download", primary: false) { Task { await offline.cancel() } }
            }
            if let error = offline.error {
                ErrorNote(message: error)
                if offline.downloadingID != nil {
                    ActionButton(title: "Retry", primary: false) { Task { await offline.retryCompletion() } }
                }
            }
            if filter == "Saved" {
                if library.favorites.isEmpty { LibraryEmptyState(title: "Build your lesson collection.", message: "Save lessons as you watch. Come back to the ideas you want to try on court.") }
                ForEach(library.favorites) { clip in
                    HStack(spacing: 14) {
                        Button { player = PlayerRoute(clips: library.favorites, startID: clip.id) } label: {
                            HStack(spacing: 14) {
                                MediaCover(url: clip.coverURL).frame(width: 76, height: 100).clipShape(RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(verbatim: clip.title).font(.court(.headline)).lineLimit(3)
                                    Text(verbatim: clip.channel).font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(PressStyle())
                        IconButton(symbol: .bookmark, label: "Remove saved video", selected: true) { library.toggle(clip) }
                    }
                }
            } else if filter == "Downloads" {
                if offline.videos.isEmpty {
                    LibraryEmptyState(title: "Available offline",
                                      message: "Download a lesson from its playback options to watch without a connection.")
                }
                ForEach(offline.videos) { video in
                    HStack(spacing: 14) {
                        Button {
                            let clips = offline.videos.compactMap { item -> LessonClip? in
                                offline.cached(item.id) == nil ? nil : offline.playable(item.clip)
                            }
                            if clips.contains(where: { $0.id == video.id }) {
                                player = PlayerRoute(clips: clips, startID: video.id)
                            } else { offline.error = "This download is no longer on this device. Download it again." }
                        } label: {
                            HStack(spacing: 14) {
                                Glyph(symbol: .download, size: 28).frame(width: 60, height: 72)
                                Text(verbatim: video.clip.title).font(.court(.headline)).lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(PressStyle())
                        VStack(spacing: 8) {
                            VideoExportEntry(clip: offline.playable(video.clip), compact: true)
                            IconButton(symbol: .close, label: "Remove download") { removingDownload = video }
                        }
                    }
                }
            } else {
                let movies = library.movies.filter { $0.isExport == (filter == "Exports") }
                if movies.isEmpty {
                    LibraryEmptyState(title: filter == "Exports" ? "Ready for your next session." : "Your practice, in focus.",
                                      message: filter == "Exports" ? "Finish a video or extract its audio in Tools. Your exports will be collected here." : "Choose your practice footage in Tools to keep a local working copy.")
                }
                ForEach(movies) { movie in
                    HStack(spacing: 12) {
                        Glyph(symbol: movie.isExport ? .download : .feed, size: 27)
                            .frame(width: 60, height: 76)
                            .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 7) {
                            Text(verbatim: movie.title).font(.court(.headline)).lineLimit(2)
                            LocalizedDateText(date: movie.date).font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    if movie.filename.hasSuffix("m4a") == false {
                                        Button("Edit") { edit(movie) }
                                    }
                                    Button(LocalizedStringKey(sharingMovieID == movie.id ? "Preparing export…" : "Export")) {
                                        guard commerce.canExportMedia else { showingExportMembership = true; return }
                                        sharingMovieID = movie.id
                                        Task {
                                            defer { sharingMovieID = nil }
                                            do { sharing = SharedFile(url: try await library.shareFile(for: movie, commerce: commerce)) }
                                            catch { library.error = error.localizedDescription }
                                        }
                                    }.disabled(sharingMovieID != nil)
                                }
                                .buttonStyle(CompactActionStyle())
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        IconButton(symbol: .close, label: "Delete local file") { removing = movie }
                    }.padding(.vertical, 8)
                }
            }
        }.clipoPage()
    }

    // Use the actual localized intrinsic widths, not device-name or language
    // breakpoints. All categories stay visible, including in narrow containers.
    private var libraryFilters: some View {
        ViewThatFits(in: .horizontal) {
            filterRow(["Saved", "Downloads", "Imports", "Exports"])
            VStack(spacing: 8) {
                filterRow(["Saved", "Downloads"])
                filterRow(["Imports", "Exports"])
            }
            VStack(spacing: 8) {
                ForEach(["Saved", "Downloads", "Imports", "Exports"], id: \.self) { value in
                    filterButton(value)
                }
            }
        }
    }

    private func filterRow(_ values: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(values, id: \.self) { value in filterButton(value) }
        }
    }

    private func categoryTitle(_ value: String) -> String {
        value == "Saved" ? "Favorites" : value == "Downloads" ? "Offline videos" : value
    }
    private func filterButton(_ value: String) -> some View {
        Button { filter = value } label: {
            LocalizedText(categoryTitle(value)).font(.court(.footnote, weight: .semibold))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(filter == value ? ClipoStyle.ink : ClipoStyle.paper)
                .background { MatteSurface(tone: filter == value ? .lime : .pine) }
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityAddTraits(filter == value ? .isSelected : [])
    }
}

// Uses the existing original bitmap action surfaces; no new system artwork.
struct OfflineDownloadButton: View {
    let clip: LessonClip
    var starting = false
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var downloadGate = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DownloadAllowanceSummary()
            if offline.cached(clip.id) != nil || clip.playbackURL.isFileURL {
                LocalizedText("Available offline").font(.court(.subheadline)).foregroundStyle(ClipoStyle.accent)
                DownloadCompletionNotice()
            } else if starting || offline.preparingID == clip.id {
                ActionButton(title: "Preparing download…", primary: false, busy: true) { }
                LocalizedText("Preparing download…").font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
            } else if offline.downloadingID == clip.id {
                LocalizedText("Downloading · \(Int(offline.progress * 100))%").font(.court(.caption))
                ActionButton(title: "Cancel download", primary: false) { Task { await offline.cancel() } }
            } else {
                ActionButton(title: "Download for offline", primary: false) {
                    if quota.mayDownload(clip.id, premium: commerce.premium) {
                        Task { await offline.download(clip) }
                    } else { downloadGate = true }
                }.disabled(offline.busy || clip.playbackURL.isFileURL)
                    .accessibilityIdentifier("player.downloadOffline")
                if offline.isRestoring {
                    LocalizedText("Restoring downloads…").font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
                } else if offline.busy {
                    LocalizedText("Another download is in progress.").font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
                }
            }
            VideoExportEntry(clip: clip)
            if let error = offline.error {
                ErrorNote(message: error)
                if offline.downloadingID == clip.id {
                    ActionButton(title: "Retry", primary: false) { Task { await offline.retryCompletion() } }
                }
            }
        }.sheet(isPresented: $downloadGate) { MembershipView(rewardKind: .download) }
    }
}

// A separate, always-visible workflow; users need not visit the cache panel.
struct VideoExportEntry: View {
    let clip: LessonClip
    var compact = false
    @State private var showingExport = false
    @EnvironmentObject private var commerce: CommerceStore
    var body: some View {
        Group {
            if compact {
                Button("Export") { showingExport = true }.buttonStyle(CompactActionStyle())
            } else {
                ActionButton(title: "Export video", primary: false) { showingExport = true }
            }
        }.accessibilityIdentifier("player.openExport")
            .sheet(isPresented: $showingExport) {
                if commerce.canExportMedia { OfflineExportSheet(clip: clip) }
                else { MembershipView(exportRequired: true) }
            }
    }
}

private struct OfflineExportSheet: View {
    let clip: LessonClip
    @Environment(\.dismiss) private var dismiss
    @StateObject private var departure = ExportDeparture()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeading(title: "Export video") { departure.request { dismiss() } }
                Text(verbatim: clip.title).font(.court(.subheadline)).lineLimit(2)
                OfflineExportButton(clip: clip)
            }.padding(22)
        }.clipoScreenBackground().presentationDetents([.medium, .large])
            .environmentObject(departure)
            .modifier(ExportDepartureProtection(departure: departure))
    }
}

// One owner for the close button, explicit cancel and interactive dismissal.
@MainActor
final class ExportDeparture: ObservableObject {
    @Published private(set) var running = false
    @Published var confirming = false
    private var cancellation: (() -> Void)?
    private var afterCancellation: (() -> Void)?
    func begin(cancel: @escaping () -> Void) { running = true; cancellation = cancel }
    func finish() {
        running = false; cancellation = nil
        confirming = false; afterCancellation = nil
    }
    func request(_ close: @escaping () -> Void = {}) {
        guard running else { close(); return }
        afterCancellation = close; confirming = true
    }
    func keepWorking() { confirming = false; afterCancellation = nil }
    func stop() {
        let close = afterCancellation
        cancellation?()
        confirming = false; afterCancellation = nil
        close?()
    }
}

struct ExportDepartureProtection: ViewModifier {
    @ObservedObject var departure: ExportDeparture
    func body(content: Content) -> some View {
        content.interactiveDismissDisabled(departure.running)
            .accessibilityHidden(departure.confirming)
            .overlay {
                if departure.confirming {
                    GeometryReader { container in
                        ScrollView {
                            VStack(spacing: 18) {
                                LocalizedText("Stop this export?").font(.court(.headline))
                                LocalizedText("The export is still in progress. Leaving now cancels it. Your video stays safe.")
                                    .font(.court(.subheadline)).foregroundStyle(ClipoStyle.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                ActionButton(title: "Keep exporting", action: departure.keepWorking)
                                ActionButton(title: "Stop export", primary: false, action: departure.stop)
                            }.padding(22).frame(maxWidth: 360)
                                .background { OriginalSurface(tone: .pine) }.padding(20)
                                .frame(maxWidth: .infinity, minHeight: container.size.height)
                        }.background(.black.opacity(0.7))
                            .accessibilityAddTraits(.isModal)
                    }
                }
            }
    }
}

struct DownloadCompletionNotice: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        Group {
            if offline.completedDownloadID != nil {
                HStack(spacing: 12) {
                    LocalizedText("Downloaded. Watch offline in Library.")
                        .font(.court(.caption)).fixedSize(horizontal: false, vertical: true)
                    Button("View") {
                        offline.completedDownloadID = nil
                        library.openDownloads()
                    }.buttonStyle(CompactActionStyle())
                    IconButton(symbol: .close, label: "Dismiss message") { offline.completedDownloadID = nil }
                }.padding(12).foregroundStyle(ClipoStyle.paper)
                    .background { OriginalSurface(tone: .pine) }
                    .padding(.horizontal, 12)
            }
        }.task(id: offline.completedDownloadID) {
            guard let notice = offline.completedDownloadID else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            if offline.completedDownloadID == notice { offline.completedDownloadID = nil }
        }
    }
}

// Uncached exports use the same download admission and completion journal.
// Export is a Plus benefit; cached copies still pass the membership check.
private struct OfflineExportButton: View {
    let clip: LessonClip
    @EnvironmentObject private var departure: ExportDeparture
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var downloadGate = false
    @State private var preparingSource = false
    @State private var exportTask: Task<Void, Never>?
    @State private var sharing: SharedFile?
    @State private var exportError: String?
    @State private var exportedFile: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActionButton(title: preparingSource ? "Preparing export…" : exportTask == nil ? "Export video" : "Exporting…",
                         primary: false, busy: exportTask != nil, action: startExport)
                .accessibilityIdentifier("player.exportVideo")
            if !clip.playbackURL.isFileURL, offline.cached(clip.id) == nil {
                LocalizedText("We download the video before exporting. Existing downloads are reused.")
                    .font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
                DownloadAllowanceSummary()
            }
            if preparingSource, offline.downloadingID == clip.id {
                LocalizedText("Downloading · \(Int(offline.progress * 100))%").font(.court(.caption))
            }
            if exportTask != nil {
                Button("Cancel export") { departure.request() }.buttonStyle(CompactActionStyle())
            }
            if let exportError { ErrorNote(message: exportError) }
        }
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $downloadGate) { MembershipView(exportRequired: true) }
        .onDisappear { exportTask?.cancel() }
    }

    private func startExport() {
        guard exportTask == nil else { return }
        guard commerce.canExportMedia else { downloadGate = true; return }
        if !clip.playbackURL.isFileURL, offline.cached(clip.id) == nil,
           !quota.mayDownload(clip.id, premium: commerce.premium) {
            downloadGate = true
            return
        }
        if let exportedFile, FileManager.default.fileExists(atPath: exportedFile.path) {
            sharing = SharedFile(url: exportedFile); return
        }
        exportError = nil
        exportTask = Task { @MainActor in
            defer { exportTask = nil; preparingSource = false; departure.finish() }
            var ownsDownload = false
            var converted: URL?
            defer { if let converted { try? FileManager.default.removeItem(at: converted) } }
            do {
                try commerce.requireMediaExport()
                var source = clip.playbackURL
                if !source.isFileURL || offline.cached(clip.id)?.isHLS == true {
                    preparingSource = true
                    // A cache request may already be finishing for this clip.
                    // Let it finish, then decide whether its result is a file
                    // or whether the original-file download is still needed.
                    if offline.downloadingID == clip.id {
                        for await downloadID in offline.$downloadingID.values {
                            try Task.checkCancellation()
                            if downloadID != clip.id { break }
                        }
                    }
                    try Task.checkCancellation()
                    if offline.cached(clip.id)?.isHLS != false, offline.downloadingID != clip.id {
                        guard !offline.busy else { throw ClipoError.service("Another download is in progress.") }
                        ownsDownload = true
                        await offline.download(clip, forExport: true)
                    }
                    // Subscribe to the shared download state, including its
                    // current value, so a very fast completion is not missed.
                    for await downloadID in offline.$downloadingID.values {
                        try Task.checkCancellation()
                        if let cached = offline.cached(clip.id), !cached.isHLS { source = cached.url; break }
                        guard downloadID == clip.id else {
                            throw ClipoError.service(offline.error ?? "Download failed. No download allowance was used.")
                        }
                    }
                    try Task.checkCancellation()
                    guard source.isFileURL else { throw ClipoError.storage }
                    preparingSource = false
                }
                var output = source
                if !["mp4", "mov", "m4v"].contains(source.pathExtension.lowercased()) {
                    let asset = AVURLAsset(url: source)
                    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
                          session.supportedFileTypes.contains(.mp4) else {
                        throw ClipoError.service("This video format cannot be exported. Please use an MP4 or MOV file.")
                    }
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                    converted = destination
                    session.outputURL = destination
                    session.outputFileType = .mp4
                    await withTaskCancellationHandler {
                        await withCheckedContinuation { continuation in
                            session.exportAsynchronously { continuation.resume() }
                        }
                    } onCancel: { session.cancelExport() }
                    try Task.checkCancellation()
                    guard session.status == .completed else {
                        throw ClipoError.service("Video export failed. Please try again.")
                    }
                    output = destination
                }
                try Task.checkCancellation()
                try commerce.requireMediaExport()
                let recording = try await library.importMovie(output, exported: true, title: clip.title)
                let url = try await library.shareFile(for: recording, commerce: commerce)
                exportedFile = url
                if !Task.isCancelled { sharing = SharedFile(url: url) }
            } catch is CancellationError {
                if ownsDownload, offline.downloadingID == clip.id { await offline.cancel() }
            }
            catch {
                exportError = error.localizedDescription
            }
        }
        departure.begin { exportTask?.cancel() }
    }
}

// Shared, live allowance display at the download decision and in the offline library.
struct DownloadAllowanceSummary: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingReward = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("Downloads left").font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
            LocalizedText(api.session == nil ? "Connect to refresh your allowance." :
                            commerce.premium || quota.downloadsUnlimited ? "Unlimited" :
                            quota.usage == nil ? "Loading…" : "\(quota.downloadsLeft) downloads left today")
                .font(.court(.subheadline, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if quota.usage != nil, !commerce.premium { AllowanceResetText() }
            if quota.canRequestReward(for: .download, premium: commerce.premium) {
                ActionButton(title: "Get more downloads", primary: false) { showingReward = true }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background { OriginalSurface(tone: .pine) }
            .accessibilityElement(children: .contain)
            .onAppear { quota.resetIfNeeded() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in quota.resetIfNeeded() }
            .sheet(isPresented: $showingReward) { MembershipView(rewardKind: .download) }
    }
}

private struct LibraryEmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            LocalizedText(title).font(.court(.headline))
            LocalizedText(message).font(.court(.subheadline)).foregroundStyle(ClipoStyle.secondary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.multilineTextAlignment(.center).padding(.horizontal, 12).padding(.vertical, 24)
            .frame(maxWidth: .infinity)
    }
}

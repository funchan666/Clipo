import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    var edit: (PracticeRecording) -> Void
    @State private var filter = "Saved"
    @State private var player: PlayerRoute?
    @State private var sharing: SharedFile?
    @State private var removing: PracticeRecording?
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
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
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
            SectionLabel(title: filter, detail: "\(itemCount) \(itemCount == 1 ? "item" : "items") · On this device")
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
                        IconButton(symbol: .close, label: "Remove download") { offline.remove(video) }
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
                                    Button("Share") { sharing = SharedFile(url: library.url(for: movie)) }
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

    private func filterButton(_ value: String) -> some View {
        Button { filter = value } label: {
            LocalizedText(value).font(.court(.footnote, weight: .semibold))
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
            if let error = offline.error {
                ErrorNote(message: error)
                if offline.downloadingID == clip.id {
                    ActionButton(title: "Retry", primary: false) { Task { await offline.retryCompletion() } }
                }
            }
        }.sheet(isPresented: $downloadGate) { MembershipView(rewardKind: .download) }
    }
}

// Shared, live allowance display at the download decision and in the offline library.
struct DownloadAllowanceSummary: View {
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingReward = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("Downloads left").font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
            LocalizedText(commerce.premium || quota.downloadsUnlimited ? "Unlimited" :
                            quota.usage == nil ? "Loading…" : "\(quota.downloadsLeft) downloads left today")
                .font(.court(.subheadline, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
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

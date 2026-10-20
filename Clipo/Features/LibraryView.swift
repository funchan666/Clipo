import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    var edit: (LocalMovie) -> Void
    @State private var filter = "Saved"
    @State private var player: PlayerRoute?
    @State private var sharing: SharedFile?
    @State private var removing: LocalMovie?
    private var itemCount: Int {
        if filter == "Downloads" { return offline.videos.count }
        return filter == "Saved" ? library.favorites.count : library.movies.filter { $0.isExport == (filter == "Exports") }.count
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if itemCount > 0 {
                    TennisArtwork(kind: .notebook, height: 128)
                }
                FlowChoices(values: ["Saved", "Downloads", "Imports", "Exports"], selected: filter) { filter = $0 }
                SectionLabel(title: filter, detail: "\(itemCount) \(itemCount == 1 ? "item" : "items") · On this device")
                if offline.downloadingID != nil {
                    if let title = offline.currentTitle { Text(verbatim: title).font(.subheadline).lineLimit(2) }
                    LocalizedText("Downloading · \(Int(offline.progress * 100))%").font(.caption)
                    ActionButton(title: "Cancel download", primary: false) { Task { await offline.cancel() } }
                }
                if let error = offline.error {
                    ErrorNote(message: error)
                    if offline.downloadingID != nil {
                        ActionButton(title: "Retry", primary: false) { Task { await offline.retryCompletion() } }
                    }
                }
                if filter == "Saved" {
                    if library.favorites.isEmpty { LibraryEmptyState(artwork: .notebook, title: "Build your lesson collection.", message: "Save lessons as you watch. Come back to the ideas you want to try on court.") }
                    ForEach(library.favorites) { clip in
                        HStack(spacing: 14) {
                            Button { player = PlayerRoute(clips: library.favorites, startID: clip.id) } label: {
                                HStack(spacing: 14) {
                                    MediaCover(url: clip.coverURL).frame(width: 76, height: 100).clipShape(RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(verbatim: clip.title).font(.headline).lineLimit(3)
                                        Text(verbatim: clip.channel).font(.caption).foregroundStyle(ClipoStyle.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.buttonStyle(PressStyle())
                            IconButton(symbol: .bookmark, label: "Remove saved video", selected: true) { library.toggle(clip) }
                        }
                    }
                } else if filter == "Downloads" {
                    if offline.videos.isEmpty {
                        LibraryEmptyState(artwork: .notebook, title: "Available offline",
                                          message: "Download a lesson from its playback options to watch without a connection.")
                    }
                    ForEach(offline.videos) { video in
                        HStack(spacing: 14) {
                            Button {
                                let clips = offline.videos.compactMap { item -> Clip? in
                                    offline.cached(item.id) == nil ? nil : offline.playable(item.clip)
                                }
                                if clips.contains(where: { $0.id == video.id }) {
                                    player = PlayerRoute(clips: clips, startID: video.id)
                                } else { offline.error = "This download is no longer on this device. Download it again." }
                            } label: {
                                HStack(spacing: 14) {
                                    Glyph(symbol: .download, size: 28).frame(width: 60, height: 72)
                                    Text(verbatim: video.clip.title).font(.headline).lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.contentShape(Rectangle())
                            }.buttonStyle(PressStyle())
                            IconButton(symbol: .close, label: "Remove download") { offline.remove(video) }
                        }
                    }
                } else {
                    let movies = library.movies.filter { $0.isExport == (filter == "Exports") }
                    if movies.isEmpty {
                        LibraryEmptyState(artwork: filter == "Exports" ? .bag : .racket,
                                          title: filter == "Exports" ? "Ready for your next session." : "Your practice, in focus.",
                                          message: filter == "Exports" ? "Finish a video or extract its audio in Tools. Your exports will be collected here." : "Choose your practice footage in Tools to keep a local working copy.")
                    }
                    ForEach(movies) { movie in
                        HStack(spacing: 12) {
                            Glyph(symbol: movie.isExport ? .download : .feed, size: 27)
                                .frame(width: 60, height: 76)
                                .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(verbatim: movie.title).font(.headline).lineLimit(2)
                                LocalizedDateText(date: movie.date).font(.caption).foregroundStyle(ClipoStyle.secondary)
                                HStack(spacing: 20) {
                                    if movie.filename.hasSuffix("m4a") == false {
                                        Button("Edit") { edit(movie) }.frame(minHeight: 44)
                                    }
                                    Button("Share") { sharing = SharedFile(url: library.url(for: movie)) }.frame(minHeight: 44)
                                }.font(.subheadline.weight(.medium)).foregroundStyle(ClipoStyle.accent)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            IconButton(symbol: .close, label: "Delete local file") { removing = movie }
                        }.padding(.vertical, 8)
                    }
                }
            }.clipoPage()
        }.clipoScreenBackground().sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
            .sheet(item: $removing) { movie in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SheetHeading(title: "Delete this local copy?") { removing = nil }
                        Text(verbatim: movie.title).font(.headline)
                        LocalizedText("The copy in Clipo will be removed. The original in Photos or Files will stay untouched.").foregroundStyle(ClipoStyle.secondary)
                        ActionButton(title: "Delete local copy") { library.delete(movie); removing = nil }
                        ActionButton(title: "Keep it", primary: false) { removing = nil }
                    }.padding(24)
                }.clipoScreenBackground().presentationDetents([.medium, .large])
            }
    }
}

// Uses the existing original bitmap action surfaces; no new system artwork.
struct OfflineDownloadButton: View {
    let clip: Clip
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var downloadGate = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if offline.cached(clip.id) != nil {
                LocalizedText("Available offline").font(.subheadline).foregroundStyle(ClipoStyle.accent)
            } else if offline.downloadingID == clip.id {
                LocalizedText("Downloading · \(Int(offline.progress * 100))%").font(.caption)
                ActionButton(title: "Cancel download", primary: false) { Task { await offline.cancel() } }
            } else {
                ActionButton(title: "Download for offline", primary: false) {
                    if quota.mayDownload(clip.id, premium: commerce.premium) {
                        Task { await offline.download(clip) }
                    } else { downloadGate = true }
                }.disabled(offline.busy || clip.playbackURL.isFileURL)
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

private struct LibraryEmptyState: View {
    let artwork: TennisArtwork.Kind
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 18) {
            TennisArtwork(kind: artwork, height: 184)
            VStack(spacing: 10) {
                LocalizedText(title).font(.title3.weight(.semibold))
                LocalizedText(message).font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }.multilineTextAlignment(.center).padding(.horizontal, 24).padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

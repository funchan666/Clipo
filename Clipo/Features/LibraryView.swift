import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    var edit: (LocalMovie) -> Void
    @State private var filter = "Saved"
    @State private var player: PlayerRoute?
    @State private var sharing: SharedFile?
    @State private var removing: LocalMovie?
    private var itemCount: Int {
        filter == "Saved" ? library.favorites.count : library.movies.filter { $0.isExport == (filter == "Exports") }.count
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if itemCount > 0 {
                    ClipoIllustration(name: "ClipoArtLibrary", height: 128)
                }
                FlowChoices(values: ["Saved", "Imports", "Exports"], selected: filter) { filter = $0 }
                SectionLabel(title: filter, detail: "\(itemCount) \(itemCount == 1 ? "item" : "items") · On this device")
                if filter == "Saved" {
                    if library.favorites.isEmpty { LibraryEmptyState(artwork: "ClipoArtLibrary", title: "Worth keeping.", message: "Save a video while watching and find it here whenever you want to come back.") }
                    ForEach(library.favorites) { clip in
                        HStack(spacing: 14) {
                            Button { player = PlayerRoute(clips: library.favorites, startID: clip.id) } label: {
                                HStack(spacing: 14) {
                                    MediaCover(url: clip.coverURL).frame(width: 76, height: 100).clipShape(RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(clip.title).font(.headline).lineLimit(3)
                                        Text(clip.channel).font(.caption).foregroundStyle(ClipoStyle.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.buttonStyle(PressStyle())
                            IconButton(symbol: .bookmark, label: "Remove saved video", selected: true) { library.toggle(clip) }
                        }
                    }
                } else {
                    let movies = library.movies.filter { $0.isExport == (filter == "Exports") }
                    if movies.isEmpty {
                        LibraryEmptyState(artwork: filter == "Exports" ? "ClipoArtExport" : "ClipoArtStudio",
                                          title: filter == "Exports" ? "Ready when you are." : "Your next edit starts here.",
                                          message: filter == "Exports" ? "Finish a video or extract its audio in Tools. Your exports will be collected here." : "Choose a video in Tools to keep a local working copy.")
                    }
                    ForEach(movies) { movie in
                        HStack(spacing: 12) {
                            Glyph(symbol: movie.isExport ? .download : .feed, size: 27)
                                .frame(width: 60, height: 76)
                                .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(movie.title).font(.headline).lineLimit(2)
                                Text(movie.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(ClipoStyle.secondary)
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
                        Text(movie.title).font(.headline)
                        Text("The copy in Clipo will be removed. The original in Photos or Files will stay untouched.").foregroundStyle(ClipoStyle.secondary)
                        ActionButton(title: "Delete local copy") { library.delete(movie); removing = nil }
                        ActionButton(title: "Keep it", primary: false) { removing = nil }
                    }.padding(24)
                }.clipoScreenBackground().presentationDetents([.medium, .large])
            }
    }
}

private struct LibraryEmptyState: View {
    let artwork: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 18) {
            ClipoIllustration(name: artwork, height: 184)
            VStack(spacing: 10) {
                Text(title).font(.title3.weight(.semibold))
                Text(message).font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }.multilineTextAlignment(.center).padding(.horizontal, 24).padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    var edit: (LocalMovie) -> Void
    @State private var filter = "Saved"
    @State private var player: PlayerRoute?
    @State private var sharing: SharedFile?
    @State private var removing: LocalMovie?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Your collection", title: "Keep the good ones.")
                FlowChoices(values: ["Saved", "Imports", "Exports"], selected: filter) { filter = $0 }
                Text("Stored on this device.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
                if filter == "Saved" {
                    if library.favorites.isEmpty { MessagePanel(title: "A collection starts with one clip.", message: "Tap Save while watching. Your saved videos will appear here.") }
                    ForEach(library.favorites) { clip in
                        HStack(spacing: 14) {
                            Button { player = PlayerRoute(clips: library.favorites, startID: clip.id) } label: {
                                HStack(spacing: 14) {
                                    MediaCover(url: clip.coverURL).frame(width: 84, height: 110).clipShape(RoundedRectangle(cornerRadius: 14))
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
                        MessagePanel(title: filter == "Exports" ? "Your finished cuts belong here." : "Bring your own footage.",
                                     message: filter == "Exports" ? "Export a video from Studio to start your collection." : "Choose a video in Studio to keep a local working copy.")
                    }
                    ForEach(movies) { movie in
                        HStack(spacing: 12) {
                            Glyph(symbol: movie.isExport ? .download : .feed, size: 30)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(movie.title).font(.headline).lineLimit(2)
                                Text(movie.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(ClipoStyle.secondary)
                                HStack(spacing: 20) {
                                    if movie.filename.hasSuffix("m4a") == false {
                                        Button("Edit") { edit(movie) }
                                    }
                                    Button("Share") { sharing = SharedFile(url: library.url(for: movie)) }
                                }.font(.subheadline.weight(.medium)).foregroundStyle(ClipoStyle.accent)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            IconButton(symbol: .close, label: "Delete local file") { removing = movie }
                        }.padding(.vertical, 8)
                    }
                }
            }.padding(22)
        }.sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
            .sheet(item: $removing) { movie in
                VStack(alignment: .leading, spacing: 22) {
                    SheetHeading(title: "Delete this local copy?") { removing = nil }
                    Text(movie.title).font(.headline)
                    Text("The copy in Clipo will be removed. The original in Photos or Files will stay untouched.").foregroundStyle(ClipoStyle.secondary)
                    ActionButton(title: "Delete local copy") { library.delete(movie); removing = nil }
                    ActionButton(title: "Keep it", primary: false) { removing = nil }
                }.padding(24).background(ClipoStyle.background).presentationDetents([.medium])
            }
    }
}

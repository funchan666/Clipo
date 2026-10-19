import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct EditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Clipo Studio") { dismiss() }
            EditorWorkspace()
        }.background(ClipoStyle.background).foregroundStyle(.white)
    }
}
struct EditorWorkspace: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    var initialMovie: LocalMovie? = nil
    @StateObject private var editor = VideoEditor()
    @State private var selected: LocalMovie?
    @State private var picker: PhotosPickerItem?
    @State private var filePicker = false
    @State private var importing = false
    @State private var error: String?
    @State private var shareURL: SharedFile?
    @State private var tool = "Trim"
    @State private var exportTask: Task<Void, Never>?
    private let tools = ["Trim", "Frame", "Speed", "Audio", "Export"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Clipo studio", title: selected == nil ? "Your next cut." : "Make the moment.")
                if let selected {
                    HStack {
                        Text(selected.title).font(.subheadline).lineLimit(1)
                        Spacer()
                        if !editor.isExporting {
                            Button("Change") { self.selected = nil; editor.close() }.foregroundStyle(ClipoStyle.accent)
                        }
                    }
                    VideoSurface(player: editor.preview.player, fill: false)
                        .frame(height: 300).background(.black).clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(alignment: .bottomTrailing) { PreviewButton(playback: editor.preview).padding(8) }
                    if editor.isLoading { Text("Preparing your video…").foregroundStyle(ClipoStyle.secondary) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tools, id: \.self) { name in
                                Button(name) { tool = name }.font(.subheadline.bold()).padding(.horizontal, 20).padding(.vertical, 12)
                                    .foregroundStyle(tool == name ? ClipoStyle.ink : .white)
                                    .background(tool == name ? ClipoStyle.accent : ClipoStyle.surface, in: Capsule()).buttonStyle(PressStyle())
                            }
                        }
                    }
                    controls.disabled(editor.isExporting || editor.isLoading)
                    if let error = editor.error { ErrorNote(message: error) }
                    if let error { ErrorNote(message: error) }
                    if editor.isExporting {
                        VStack(spacing: 14) {
                            Text("Exporting · \(Int(editor.progress * 100))%").font(.headline.monospacedDigit())
                            GeometryReader { geometry in
                                Color.clear.background(ClipoStyle.raised)
                                    .overlay(alignment: .leading) { ClipoStyle.accent.frame(width: geometry.size.width * CGFloat(editor.progress)) }
                            }.frame(height: 4)
                            ActionButton(title: "Cancel export", primary: false) { editor.cancelExport() }
                        }
                    } else {
                        ActionButton(title: "Export video") { export(audio: false, title: selected.title) }
                            .disabled(editor.isLoading || editor.duration <= 0)
                        ActionButton(title: "Preview changes", primary: false) { Task { await editor.applyPreview() } }
                            .disabled(editor.isLoading || editor.duration <= 0)
                    }
                    Text("Your original stays untouched. Exports are saved to your local library.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        Glyph(symbol: .edit, size: 62)
                        Text("A little less.\nA lot more you.").font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        Text("Trim the timing, change the frame, find the pace. Start with a video on your device.")
                            .font(.body).foregroundStyle(ClipoStyle.secondary).lineSpacing(4)
                        PhotosPicker(selection: $picker, matching: .videos, photoLibrary: .shared()) {
                            Text(importing ? "Importing…" : "Choose from Photos").font(.body.bold())
                                .frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(ClipoStyle.ink)
                                .background(ClipoStyle.accent, in: RoundedRectangle(cornerRadius: 18))
                        }.disabled(importing).buttonStyle(PressStyle())
                        ActionButton(title: "Browse Files", primary: false, busy: importing) { filePicker = true }
                    }.padding(24).background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 26))
                    if let error { ErrorNote(message: error) }
                    if !library.movies.filter({ !$0.isExport }).isEmpty {
                        Text("Continue with a video").font(.title3.bold())
                        ForEach(library.movies.filter { !$0.isExport }) { movie in
                            Button { choose(movie) } label: {
                                HStack(spacing: 14) {
                                    Glyph(symbol: .feed, size: 28)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(movie.title).font(.headline).lineLimit(1)
                                        Text(movie.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(ClipoStyle.secondary)
                                    }
                                    Spacer()
                                    Glyph(symbol: .edit, size: 22)
                                }.padding(.vertical, 8)
                            }.buttonStyle(PressStyle())
                        }
                    }
                }
            }.padding(22).padding(.bottom, 18)
        }.background(ClipoStyle.background)
            .fileImporter(isPresented: $filePicker, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
                do { if let url = try result.get().first { importURL(url) } }
                catch { self.error = error.localizedDescription }
            }
            .onChange(of: picker) { _, item in
                guard let item else { return }
                importing = true
                error = nil
                Task {
                    defer { importing = false; picker = nil }
                    do {
                        guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else { throw ClipoError.unsupportedMedia }
                        defer { try? FileManager.default.removeItem(at: movie.url) }
                        let saved = try await library.importMovie(movie.url, title: "Imported video")
                        selected = saved
                        await editor.open(library.url(for: saved))
                    } catch { self.error = error.localizedDescription }
                }
            }
            .sheet(item: $shareURL) { ShareSheet(items: [$0.url]) }
            .task { if let initialMovie, selected == nil { selected = initialMovie; await editor.open(library.url(for: initialMovie)) } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { editor.preview.pause() } }
            .onDisappear { editor.close(); exportTask?.cancel() }
    }
    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch tool {
            case "Trim":
                Text("Keep the good part.").font(.title3.bold())
                if !editor.thumbnails.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(Array(editor.thumbnails.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 42, height: 64).clipped()
                            }
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 10))
                }
                HStack { Text("Start"); Spacer(); Text(durationLabel(editor.recipe.start)).monospacedDigit() }
                ClipoScrubber(value: Binding(get: { editor.recipe.start }, set: { editor.recipe.start = min($0, editor.recipe.end - 0.1); editor.preview.seek($0) }), range: 0...max(0.1, editor.duration), label: "Trim start")
                HStack { Text("End"); Spacer(); Text(durationLabel(editor.recipe.end)).monospacedDigit() }
                ClipoScrubber(value: Binding(get: { editor.recipe.end }, set: { editor.recipe.end = max($0, editor.recipe.start + 0.1) }), range: 0...max(0.1, editor.duration), label: "Trim end")
                Text("Final duration · \(durationLabel((editor.recipe.end - editor.recipe.start) / editor.recipe.speed))").font(.footnote).foregroundStyle(ClipoStyle.accent)
            case "Frame":
                Text("Find the frame.").font(.title3.bold())
                FlowChoices(values: VideoFrame.allCases.map(\.rawValue), selected: editor.recipe.frame.rawValue) { value in editor.recipe.frame = VideoFrame(rawValue: value) ?? .original }
                ActionButton(title: "Rotate 90° · \((editor.recipe.quarterTurns % 4) * 90)°", primary: false) { editor.recipe.quarterTurns = (editor.recipe.quarterTurns + 1) % 4 }
                ActionButton(title: editor.recipe.mirrored ? "Mirror: On" : "Mirror: Off", primary: false) { editor.recipe.mirrored.toggle() }
                Text("Frames crop from the center. Use Preview changes to inspect the result.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
            case "Speed":
                Text("Set the pace.").font(.title3.bold())
                FlowChoices(values: ["0.5×", "0.75×", "1×", "1.5×", "2×"], selected: String(format: "%g×", editor.recipe.speed)) { value in editor.recipe.speed = Double(value.replacingOccurrences(of: "×", with: "")) ?? 1 }
            case "Audio":
                Text("Let it speak. Or don’t.").font(.title3.bold())
                ActionButton(title: editor.recipe.muted ? "Audio: Muted" : "Audio: Original", primary: false) { editor.recipe.muted.toggle() }
                ActionButton(title: "Extract audio as M4A", primary: false) { export(audio: true, title: selected?.title ?? "Audio") }
                Text("Audio extraction uses your trim and speed settings.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
            default:
                Text("Ready for its next screen.").font(.title3.bold())
                FlowChoices(values: ExportQuality.allCases.map(\.rawValue), selected: editor.recipe.quality.rawValue) { value in editor.recipe.quality = ExportQuality(rawValue: value) ?? .full }
                Text("MP4 · Up to the selected resolution · 30 fps\nSmaller resolutions reduce export size. Source videos are never upscaled.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
            }
        }.padding(20).background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }
    private func choose(_ movie: LocalMovie) { selected = movie; error = nil; Task { await editor.open(library.url(for: movie)) } }
    private func importURL(_ url: URL) {
        importing = true
        error = nil
        Task {
            defer { importing = false }
            do { let movie = try await library.importMovie(url); choose(movie) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func export(audio: Bool, title: String) {
        error = nil
        exportTask = Task {
            guard let output = await editor.export(audioOnly: audio) else { return }
            if Task.isCancelled { try? FileManager.default.removeItem(at: output); return }
            do {
                let saved = try await library.importMovie(output, exported: true, title: title + (audio ? " · Audio" : " · Edit"))
                try? FileManager.default.removeItem(at: output)
                shareURL = SharedFile(url: library.url(for: saved))
            } catch { self.error = "The export finished but could not be added to your library. \(error.localizedDescription)" }
        }
    }
}
struct PreviewButton: View {
    @ObservedObject var playback: PlaybackController
    var body: some View {
        IconButton(symbol: playback.isPlaying ? .pause : .play, label: playback.isPlaying ? "Pause preview" : "Play preview") { playback.toggle() }
            .background(.black.opacity(0.65), in: Circle())
    }
}
struct FlowChoices: View {
    let values: [String]
    let selected: String
    var action: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
            ForEach(values, id: \.self) { value in
                Button(value) { action(value) }.font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(value == selected ? ClipoStyle.ink : .white)
                    .background(value == selected ? ClipoStyle.accent : ClipoStyle.raised, in: RoundedRectangle(cornerRadius: 12))
                    .buttonStyle(PressStyle()).accessibilityAddTraits(value == selected ? .isSelected : [])
            }
        }
    }
}
struct SharedFile: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

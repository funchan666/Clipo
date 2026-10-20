import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum VideoTool: String, Identifiable, CaseIterable {
    case audio, speed, frame, studio
    var id: String { rawValue }
    var title: String {
        switch self {
        case .audio: return "Extract audio"
        case .speed: return "Change speed"
        case .frame: return "Reframe video"
        case .studio: return "Full editor"
        }
    }
    var detail: String {
        switch self {
        case .audio: return "Keep the sound as an M4A file."
        case .speed: return "Slow it down or pick up the pace."
        case .frame: return "Portrait, square or landscape."
        case .studio: return "Trim, rotate and combine your changes."
        }
    }
    var editorTab: String {
        switch self {
        case .audio: return "Audio"
        case .speed: return "Speed"
        case .frame: return "Frame"
        case .studio: return "Trim"
        }
    }
    var glyph: ClipoGlyph {
        switch self {
        case .audio: return .sound
        case .speed: return .play
        case .frame: return .feed
        case .studio: return .edit
        }
    }
}

struct ToolsView: View {
    @State private var selectedTool: VideoTool?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ClipoIllustration(name: "ClipoArtTools", height: 176)
                Text("Quick tools for videos on your device. Your original stays untouched.")
                    .font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                VStack(spacing: 0) {
                    ForEach([VideoTool.audio, .speed, .frame]) { tool in
                        Button { selectedTool = tool } label: {
                            HStack(spacing: 16) {
                                Glyph(symbol: tool.glyph, size: 26).allowsHitTesting(false)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(tool.title).font(.headline)
                                    Text(tool.detail).font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 20).padding(.horizontal, 20)
                                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                                .contentShape(.interaction, Rectangle())
                        }.buttonStyle(PressStyle()).accessibilityIdentifier("tools.\(tool.rawValue)")
                        if tool != .frame { Divider().overlay(ClipoStyle.line).padding(.horizontal, 20) }
                    }
                }.background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                ActionButton(title: "Open full editor", primary: false) { selectedTool = .studio }
                Text("Processed on your device. Finished files appear in Library under Exports.")
                    .font(.footnote).foregroundStyle(ClipoStyle.secondary)
            }.clipoPage()
        }.clipoScreenBackground()
            .sheet(item: $selectedTool) { EditorSheet(initialTool: $0) }
    }
}

struct EditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialMovie: LocalMovie? = nil
    var initialTool: VideoTool = .studio
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: initialTool.title) { dismiss() }
            EditorWorkspace(initialMovie: initialMovie, initialTool: initialTool)
        }.clipoScreenBackground().foregroundStyle(.white)
    }
}
struct EditorWorkspace: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    var initialMovie: LocalMovie? = nil
    var initialTool: VideoTool = .studio
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
    init(initialMovie: LocalMovie? = nil, initialTool: VideoTool = .studio) {
        self.initialMovie = initialMovie
        self.initialTool = initialTool
        _tool = State(initialValue: initialTool.editorTab)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if selected == nil {
                    Text(initialTool.detail)
                        .font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                }
                if let selected {
                    HStack {
                        Text(selected.title).font(.subheadline).lineLimit(1)
                        Spacer()
                        if !editor.isExporting, !editor.isPreparingPreview {
                            Button("Change") { self.selected = nil; editor.close() }.foregroundStyle(ClipoStyle.accent)
                        }
                    }
                    VideoSurface(player: editor.preview.player, fill: false)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit).background(.black).clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(alignment: .bottomTrailing) { PreviewButton(playback: editor.preview).padding(8) }
                    if editor.isLoading { Text("Preparing your video…").foregroundStyle(ClipoStyle.secondary) }
                    if editor.isPreparingPreview { AccountLoadingIndicator(title: "Preparing preview…").frame(maxWidth: .infinity) }
                    if initialTool == .studio {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tools, id: \.self) { name in
                                    Button(name) { tool = name }.font(.subheadline.weight(.semibold)).padding(.horizontal, 20).frame(minHeight: 48)
                                        .foregroundStyle(tool == name ? ClipoStyle.ink : .white)
                                        .background(tool == name ? ClipoStyle.accent : ClipoStyle.surface, in: Capsule()).buttonStyle(PressStyle())
                                        .accessibilityAddTraits(tool == name ? .isSelected : [])
                                }
                            }
                        }
                    }
                    controls.disabled(editor.isExporting || editor.isLoading || editor.isPreparingPreview)
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
                        ActionButton(title: initialTool == .audio ? "Export audio as M4A" : "Export video") {
                            export(audio: initialTool == .audio, title: selected.title)
                        }
                            .disabled(editor.isLoading || editor.isPreparingPreview || editor.duration <= 0)
                        ActionButton(title: "Preview changes", primary: false) { Task { await editor.applyPreview() } }
                            .disabled(editor.isLoading || editor.isPreparingPreview || editor.duration <= 0)
                    }
                    Text("Your original stays untouched. Exports are saved to your local library.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        ClipoIllustration(name: initialTool == .studio ? "ClipoArtStudio" : "ClipoArtTools", height: 176)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Start with a video.").font(.title2.weight(.bold)).tracking(-0.5)
                            Text("Choose a clip from your device. We’ll keep your original untouched.")
                                .font(.subheadline).foregroundStyle(ClipoStyle.secondary).lineSpacing(3)
                        }
                        VStack(spacing: 10) {
                            PhotosPicker(selection: $picker, matching: .videos, photoLibrary: .shared()) {
                                Text(importing ? "Importing…" : "Choose from Photos").font(.body.weight(.semibold))
                                    .padding(.horizontal, 16).padding(.vertical, 16)
                                    .frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(ClipoStyle.ink)
                                    .background(ClipoStyle.accent, in: RoundedRectangle(cornerRadius: 16))
                            }.disabled(importing).buttonStyle(PressStyle())
                            ActionButton(title: "Browse Files", primary: false, busy: importing) { filePicker = true }
                        }
                    }.padding(24).background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                    if initialTool == .studio {
                        VStack(alignment: .leading, spacing: 18) {
                            SectionLabel(title: "From raw to ready")
                            FeatureRow(symbol: .edit, title: "Keep the best part", detail: "Trim the timing, crop the frame, change the pace.")
                            HStack(spacing: 16) {
                                ClipoIllustration(name: "ClipoArtExport", height: 72).frame(width: 108)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Export your way").font(.subheadline.weight(.semibold))
                                    Text("Save a video or extract an audio track.").font(.caption)
                                        .foregroundStyle(ClipoStyle.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if let error { ErrorNote(message: error) }
                    if !library.movies.filter({ !$0.isExport }).isEmpty {
                        SectionLabel(title: "Recent imports")
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
            }.clipoPage()
        }.clipoScreenBackground()
            .onReceive(editor.preview.$error) { message in
                if let message { editor.error = "Preview could not play. \(message)" }
            }
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
                if initialTool == .audio {
                    Text("Keep the soundtrack.").font(.title3.bold())
                    Text("Extract the original audio track into an M4A file. Videos without an audio track cannot be converted.")
                        .font(.subheadline).foregroundStyle(ClipoStyle.secondary)
                } else {
                    Text("Let it speak. Or don’t.").font(.title3.bold())
                    ActionButton(title: editor.recipe.muted ? "Audio: Muted" : "Audio: Original", primary: false) { editor.recipe.muted.toggle() }
                    ActionButton(title: "Extract audio as M4A", primary: false) { export(audio: true, title: selected?.title ?? "Audio") }
                    Text("Audio extraction uses your trim and speed settings.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
                }
            default:
                Text("Ready for its next screen.").font(.title3.bold())
                FlowChoices(values: ExportQuality.allCases.map(\.rawValue), selected: editor.recipe.quality.rawValue) { value in editor.recipe.quality = ExportQuality(rawValue: value) ?? .full }
                Text("MP4 · Up to the selected resolution · 30 fps\nSmaller resolutions reduce export size. Source videos are never upscaled.").font(.footnote).foregroundStyle(ClipoStyle.secondary)
            }
        }.padding(22).background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 20))
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 8) {
            ForEach(values, id: \.self) { value in
                Button(value) { action(value) }.font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center).padding(.horizontal, 10).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(value == selected ? ClipoStyle.ink : .white)
                    .background(value == selected ? ClipoStyle.accent : ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 14))
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

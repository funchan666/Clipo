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
        case .speed: return "Slow down your serve or review a rally."
        case .frame: return "Bring your footwork or swing into focus."
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
    @State private var showingGuide = false
    @State private var showingServePractice = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private let tools: [VideoTool] = [.speed, .frame, .audio]
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // Artwork alone extends behind the status area; controls stay below it.
                    CourtArtwork(subject: .review)
                        .frame(height: min(geometry.size.width * 0.82, 420) + geometry.safeAreaInsets.top)
                    VStack(spacing: 18) {
                        Button { selectedTool = .studio } label: {
                            LocalizedText("Review practice").font(.court(.subheadline, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 18).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(ClipoStyle.ink)
                                .background { OriginalSurface(tone: .ivory) }
                                .contentShape(Rectangle())
                        }.buttonStyle(PressStyle()).accessibilityIdentifier("tools.studio")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 220 : 92), spacing: 12)], alignment: .leading, spacing: 16) {
                            ForEach(tools) { tool in
                                Button { selectedTool = tool } label: {
                                    VStack(spacing: 8) {
                                        CourtArtwork(subject: subject(tool)).aspectRatio(1, contentMode: .fit)
                                        LocalizedText(tool.editorTab).font(.court(.footnote, weight: .semibold))
                                            .lineLimit(1).minimumScaleFactor(0.8)
                                            .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 44)
                                            .background { OriginalSurface(tone: .pine) }
                                    }.foregroundStyle(ClipoStyle.paper).contentShape(Rectangle())
                                }.buttonStyle(PressStyle())
                                    .accessibilityLabel(LocalizedStringKey(tool.title))
                                    .accessibilityIdentifier("tools.\(tool.rawValue)")
                            }
                        }
                        TennisGuideEntry { showingGuide = true }
                        ServePracticeEntry { showingServePractice = true }
                    }.clipoPage()
                }
            }.ignoresSafeArea(.container, edges: .top)
        }.clipoScreenBackground()
            .sheet(item: $selectedTool) { EditorSheet(initialTool: $0) }
            .sheet(isPresented: $showingGuide) { TennisGuideView() }
            .sheet(isPresented: $showingServePractice) { ServePracticeView() }
    }
    private func subject(_ tool: VideoTool) -> CourtArtwork.Subject {
        switch tool { case .speed: .speed; case .frame: .frame; case .audio: .audio; case .studio: .review }
    }
}

struct EditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialMovie: PracticeRecording? = nil
    var initialTool: VideoTool = .studio
    @StateObject private var departure = ExportDeparture()
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: initialTool.title) { departure.request { dismiss() } }
            EditorWorkspace(initialMovie: initialMovie, initialTool: initialTool)
        }.clipoScreenBackground().foregroundStyle(.white)
            .environmentObject(departure)
            .modifier(ExportDepartureProtection(departure: departure))
    }
}
struct EditorWorkspace: View {
    @EnvironmentObject private var departure: ExportDeparture
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    var initialMovie: PracticeRecording? = nil
    var initialTool: VideoTool = .studio
    @StateObject private var editor = VideoEditor()
    @State private var selected: PracticeRecording?
    @State private var picker: PhotosPickerItem?
    @State private var filePicker = false
    @State private var importing = false
    @State private var error: String?
    @State private var shareURL: SharedFile?
    @State private var tool = "Trim"
    @State private var exportTask: Task<Void, Never>?
    private let tools = ["Trim", "Frame", "Speed", "Audio", "Export"]
    init(initialMovie: PracticeRecording? = nil, initialTool: VideoTool = .studio) {
        self.initialMovie = initialMovie
        self.initialTool = initialTool
        _tool = State(initialValue: initialTool.editorTab)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if selected == nil {
                    LocalizedText(initialTool.detail)
                        .font(.court(.subheadline)).foregroundStyle(ClipoStyle.secondary)
                }
                if let selected {
                    HStack {
                        LocalizedText(selected.title).font(.court(.subheadline)).lineLimit(1)
                        Spacer()
                        if !departure.running, !editor.isExporting, !editor.isPreparingPreview {
                            Button("Change") { self.selected = nil; editor.close() }
                                .buttonStyle(CompactActionStyle())
                        }
                    }
                    VideoSurface(player: editor.preview.player, fill: false)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit).background(.black).clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(alignment: .bottomTrailing) { PreviewButton(playback: editor.preview).padding(8) }
                    if editor.isLoading { LocalizedText("Preparing your video…").foregroundStyle(ClipoStyle.secondary) }
                    if editor.isPreparingPreview { AccountLoadingIndicator(title: "Preparing preview…").frame(maxWidth: .infinity) }
                    if initialTool == .studio {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tools, id: \.self) { name in
                                    Button(LocalizedStringKey(name)) { tool = name }.font(.court(.subheadline, weight: .semibold))
                                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                        .padding(.horizontal, 20).frame(minHeight: 48)
                                        .foregroundStyle(tool == name ? ClipoStyle.ink : .white)
                                        .background { OriginalSurface(tone: tool == name ? .accent : .pine) }.buttonStyle(PressStyle())
                                        .accessibilityAddTraits(tool == name ? .isSelected : [])
                                }
                            }
                        }
                    }
                    controls.disabled(departure.running || editor.isExporting || editor.isLoading || editor.isPreparingPreview)
                    if let error = editor.error { ErrorNote(message: error) }
                    if let error { ErrorNote(message: error) }
                    if departure.running {
                        VStack(spacing: 14) {
                            LocalizedText(editor.isExporting ? "Exporting · \(Int(editor.progress * 100))%" : "Preparing export…")
                                .font(.court(.subheadline)).monospacedDigit()
                            GeometryReader { geometry in
                                Color.clear.background(ClipoStyle.raised)
                                    .overlay(alignment: .leading) { ClipoStyle.accent.frame(width: geometry.size.width * CGFloat(editor.progress)) }
                            }.frame(height: 4)
                            ActionButton(title: "Cancel export", primary: false) { departure.request() }
                        }
                    } else {
                        ActionButton(title: initialTool == .audio ? "Export audio as M4A" : "Export video") {
                            export(audio: initialTool == .audio, title: selected.title)
                        }
                            .disabled(editor.isLoading || editor.isPreparingPreview || editor.duration <= 0)
                        ActionButton(title: "Preview changes", primary: false) { Task { await editor.applyPreview() } }
                            .disabled(editor.isLoading || editor.isPreparingPreview || editor.duration <= 0)
                    }
                    LocalizedText("Your original stays untouched. Exports are saved to your local library.").font(.court(.footnote)).foregroundStyle(ClipoStyle.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        TennisArtwork(kind: .lesson, height: 144)
                        VStack(alignment: .leading, spacing: 10) {
                            LocalizedText("Start with a video.").font(.court(.headline))
                            LocalizedText("Choose a clip from your device. We’ll keep your original untouched.")
                                .font(.court(.subheadline)).foregroundStyle(ClipoStyle.secondary).lineSpacing(3)
                        }
                        VStack(spacing: 10) {
                            PhotosPicker(selection: $picker, matching: .videos, photoLibrary: .shared()) {
                                LocalizedText(importing ? "Importing…" : "Choose from Photos").font(.court(.subheadline, weight: .semibold))
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(ClipoStyle.ink)
                                    .background { OriginalSurface(tone: .accent) }
                                    .contentShape(Rectangle())
                            }.disabled(importing).buttonStyle(PressStyle())
                            ActionButton(title: "Browse Files", primary: false, busy: importing) { filePicker = true }
                        }
                    }.padding(20).background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                    if initialTool == .studio {
                        VStack(alignment: .leading, spacing: 18) {
                            SectionLabel(title: "From raw to ready")
                            FeatureRow(symbol: .edit, title: "Keep the best part", detail: "Trim the timing, crop the frame, change the pace.")
                            HStack(spacing: 16) {
                                TennisArtwork(kind: .bag, height: 72).frame(width: 108)
                                VStack(alignment: .leading, spacing: 6) {
                                    LocalizedText("Export your way").font(.court(.subheadline, weight: .semibold))
                                    LocalizedText("Save a video or extract an audio track.").font(.court(.caption))
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
                                        Text(verbatim: movie.title).font(.court(.headline)).lineLimit(1)
                                        LocalizedDateText(date: movie.date).font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
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
                catch { if !isCancelledImport(error) { self.error = error.localizedDescription } }
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
                    } catch { if !isCancelledImport(error) { self.error = error.localizedDescription } }
                }
            }
            .sheet(item: $shareURL) { ShareSheet(items: [$0.url]) }
            .task { if let initialMovie, selected == nil { selected = initialMovie; await editor.open(library.url(for: initialMovie)) } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { editor.preview.pause() } }
            .onDisappear { editor.close(); exportTask?.cancel() }
    }
    private func isCancelledImport(_ error: Error) -> Bool {
        let failure = error as NSError
        return error is CancellationError
            || (failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError)
            || (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled)
    }

    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch tool {
            case "Trim":
                LocalizedText("Keep the good part.").font(.court(.title3, weight: .bold))
                if !editor.thumbnails.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(Array(editor.thumbnails.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 42, height: 64).clipped()
                            }
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 10))
                }
                HStack { LocalizedText("Start"); Spacer(); Text(verbatim: durationLabel(editor.recipe.start)).monospacedDigit() }
                ClipoScrubber(value: Binding(get: { editor.recipe.start }, set: { editor.recipe.start = min($0, editor.recipe.end - 0.1); editor.preview.seek($0) }), range: 0...max(0.1, editor.duration), label: "Trim start")
                HStack { LocalizedText("End"); Spacer(); Text(verbatim: durationLabel(editor.recipe.end)).monospacedDigit() }
                ClipoScrubber(value: Binding(get: { editor.recipe.end }, set: { editor.recipe.end = max($0, editor.recipe.start + 0.1) }), range: 0...max(0.1, editor.duration), label: "Trim end")
                LocalizedText("Final duration · \(durationLabel((editor.recipe.end - editor.recipe.start) / editor.recipe.speed))").font(.court(.footnote)).foregroundStyle(ClipoStyle.accent)
            case "Frame":
                LocalizedText("Find the frame.").font(.court(.title3, weight: .bold))
                FlowChoices(values: VideoFrame.allCases.map(\.rawValue), selected: editor.recipe.frame.rawValue) { value in editor.recipe.frame = VideoFrame(rawValue: value) ?? .original }
                ActionButton(title: "Rotate 90° · \((editor.recipe.quarterTurns % 4) * 90)°", primary: false) { editor.recipe.quarterTurns = (editor.recipe.quarterTurns + 1) % 4 }
                ActionButton(title: editor.recipe.mirrored ? "Mirror: On" : "Mirror: Off", primary: false) { editor.recipe.mirrored.toggle() }
                LocalizedText("Frames crop from the center. Use Preview changes to inspect the result.").font(.court(.footnote)).foregroundStyle(ClipoStyle.secondary)
            case "Speed":
                LocalizedText("Set the pace.").font(.court(.title3, weight: .bold))
                FlowChoices(values: ["0.5×", "0.75×", "1×", "1.5×", "2×"], selected: String(format: "%g×", editor.recipe.speed)) { value in editor.recipe.speed = Double(value.replacingOccurrences(of: "×", with: "")) ?? 1 }
            case "Audio":
                if initialTool == .audio {
                    LocalizedText("Keep the soundtrack.").font(.court(.title3, weight: .bold))
                    LocalizedText("Extract the original audio track into an M4A file. Videos without an audio track cannot be converted.")
                        .font(.court(.subheadline)).foregroundStyle(ClipoStyle.secondary)
                } else {
                    LocalizedText("Let it speak. Or don’t.").font(.court(.title3, weight: .bold))
                    ActionButton(title: editor.recipe.muted ? "Audio: Muted" : "Audio: Original", primary: false) { editor.recipe.muted.toggle() }
                    ActionButton(title: "Extract audio as M4A", primary: false) { export(audio: true, title: selected?.title ?? "Audio") }
                    LocalizedText("Audio extraction uses your trim and speed settings.").font(.court(.footnote)).foregroundStyle(ClipoStyle.secondary)
                }
            default:
                LocalizedText("Ready for its next screen.").font(.court(.title3, weight: .bold))
                FlowChoices(values: ExportQuality.allCases.map(\.rawValue), selected: editor.recipe.quality.rawValue) { value in editor.recipe.quality = ExportQuality(rawValue: value) ?? .full }
                LocalizedText("MP4 · Up to the selected resolution · 30 fps\nSmaller resolutions reduce export size. Source videos are never upscaled.").font(.court(.footnote)).foregroundStyle(ClipoStyle.secondary)
            }
        }.padding(22).background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private func choose(_ movie: PracticeRecording) { selected = movie; error = nil; Task { await editor.open(library.url(for: movie)) } }
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
        guard exportTask == nil else { return }
        error = nil
        exportTask = Task {
            defer { exportTask = nil; departure.finish() }
            guard let output = await editor.export(audioOnly: audio) else { return }
            if Task.isCancelled { try? FileManager.default.removeItem(at: output); return }
            do {
                let saved = try await library.importMovie(output, exported: true, title: title + (audio ? " · Audio" : " · Edit"))
                try? FileManager.default.removeItem(at: output)
                let share = try await library.shareFile(for: saved)
                if !Task.isCancelled { shareURL = SharedFile(url: share) }
            } catch is CancellationError { }
            catch { self.error = "The export finished but could not be added to your library. \(error.localizedDescription)" }
        }
        departure.begin { exportTask?.cancel(); editor.cancelExport() }
    }
}
struct PreviewButton: View {
    @ObservedObject var playback: PlaybackController
    var body: some View {
        IconButton(symbol: playback.isPlaying ? .pause : .play, label: playback.isPlaying ? "Pause preview" : "Play preview") { playback.toggle() }
            .background { OriginalSurface(tone: .pine) }
    }
}
struct FlowChoices: View {
    let values: [String]
    let selected: String
    var action: (String) -> Void
    var body: some View {
        CourtFilter(values: values, selected: selected, select: action)
    }
}
struct SharedFile: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

import Foundation
import Combine
import CoreTransferable
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LessonLibrarySnapshot()
    @Published var error: String?
    private let root: URL
    private let snapshotURL: URL
    private var readable = true

    init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ClipoMedia", isDirectory: true)
        snapshotURL = root.appendingPathComponent("library.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: snapshotURL.path) {
                snapshot = try JSONDecoder().decode(LessonLibrarySnapshot.self, from: Data(contentsOf: snapshotURL))
            }
        } catch {
            readable = false
            self.error = "Your local library could not be read. Existing files have been preserved."
        }
    }
    var movies: [PracticeRecording] { snapshot.movies }
    var favorites: [LessonClip] { snapshot.favorites }
    var history: [LessonLinkVisit] { snapshot.history }
    func url(for movie: PracticeRecording) -> URL { root.appendingPathComponent(movie.filename) }
    func isSaved(_ clip: LessonClip) -> Bool { favorites.contains { $0.id == clip.id } }
    func toggle(_ clip: LessonClip) {
        var next = snapshot
        if isSaved(clip) { next.favorites.removeAll { $0.id == clip.id } }
        else { next.favorites.insert(clip, at: 0) }
        save(next)
    }
    func record(link: String, title: String) {
        var next = snapshot
        next.history.removeAll { $0.link == link }
        next.history.insert(LessonLinkVisit(id: UUID(), link: link, title: title, date: Date()), at: 0)
        next.history = Array(next.history.prefix(100))
        save(next)
    }
    func clearHistory() {
        var next = snapshot
        next.history = []
        save(next)
    }
    func removeVisit(_ visit: LessonLinkVisit) {
        var next = snapshot
        next.history.removeAll { $0.id == visit.id }
        save(next)
    }
    func importMovie(_ source: URL, exported: Bool = false, title: String? = nil) async throws -> PracticeRecording {
        guard readable else { throw ClipoError.storage }
        let id = UUID()
        let ext = source.pathExtension.lowercased().nilIfBlank ?? "mov"
        let item = PracticeRecording(id: id, filename: id.uuidString + "." + ext,
                              title: title ?? source.deletingPathExtension().lastPathComponent,
                              date: Date(), isExport: exported)
        let destination = url(for: item)
        try await Task.detached(priority: .userInitiated) {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: source, to: destination)
        }.value
        var next = snapshot
        next.movies.insert(item, at: 0)
        do { try persist(next) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
        return item
    }
    func delete(_ movie: PracticeRecording) {
        // Commit index removal first; a failed file deletion leaves an orphan, not a broken library entry.
        var next = snapshot
        next.movies.removeAll { $0.id == movie.id }
        do {
            try persist(next)
            let file = url(for: movie)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        } catch { self.error = error.localizedDescription }
    }
    private func save(_ next: LessonLibrarySnapshot) {
        do { try persist(next) } catch { self.error = error.localizedDescription }
    }
    private func persist(_ next: LessonLibrarySnapshot) throws {
        guard readable else { throw ClipoError.storage }
        let data = try JSONEncoder().encode(next)
        try data.write(to: snapshotURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let saved = try Data(contentsOf: snapshotURL)
        guard saved == data else { throw ClipoError.storage }
        snapshot = next
    }
}

struct ImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in SentTransferredFile(movie.url) }
        importing: { received in
            let ext = received.file.pathExtension.nilIfBlank ?? "mov"
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return ImportedMovie(url: copy)
        }
    }
}

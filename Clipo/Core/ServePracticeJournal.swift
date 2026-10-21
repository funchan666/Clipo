import Foundation
import Combine

enum ServiceCourt: String, Codable, CaseIterable, Identifiable {
    case deuce, advantage
    var id: String { rawValue }
    var label: String { self == .deuce ? "Deuce court" : "Ad court" }
}

enum ServeTarget: String, Codable, CaseIterable, Identifiable {
    case wide, body, centreT
    var id: String { rawValue }
    var label: String {
        switch self { case .wide: "Wide target"; case .body: "Body target"; case .centreT: "T target" }
    }
}

enum ServeLanding: String, Codable, CaseIterable, Identifiable {
    case targetHit, inBox, net, out
    var id: String { rawValue }
    var label: String {
        switch self { case .targetHit: "Target hit"; case .inBox: "In, off target"; case .net: "Into net"; case .out: "Outside box" }
    }
    var landedIn: Bool { self == .targetHit || self == .inBox }
}

struct ServeAttempt: Codable, Identifiable {
    let id: UUID
    let recordedAt: Date
    let serviceCourt: ServiceCourt
    let intendedTarget: ServeTarget
    let landingResult: ServeLanding
}

struct ServePracticeSession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    var finishedAt: Date?
    var attempts: [ServeAttempt]
    var inCount: Int { attempts.filter { $0.landingResult.landedIn }.count }
    var targetCount: Int { attempts.filter { $0.landingResult == .targetHit }.count }
    var targetPercentage: Int { attempts.isEmpty ? 0 : Int((Double(targetCount) / Double(attempts.count) * 100).rounded()) }
}

private struct ServeJournalArchive: Codable {
    var activeSession: ServePracticeSession?
    var completedSessions: [ServePracticeSession] = []
}

@MainActor
final class ServePracticeJournal: ObservableObject {
    @Published private var archive = ServeJournalArchive()
    @Published private(set) var storageMessage: String?
    private let archiveURL: URL
    private var storageReadable = true
    var activeSession: ServePracticeSession? { archive.activeSession }
    var completedSessions: [ServePracticeSession] { archive.completedSessions }
    var available: Bool { storageReadable }

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ServePractice", isDirectory: true)
        archiveURL = folder.appendingPathComponent("sessions.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                archive = try JSONDecoder().decode(ServeJournalArchive.self, from: Data(contentsOf: archiveURL))
            }
        } catch {
            storageReadable = false
            storageMessage = "Practice records could not be opened. Existing records are preserved."
        }
    }

    func beginSession() {
        guard activeSession == nil else { return }
        var next = archive
        next.activeSession = ServePracticeSession(id: UUID(), startedAt: Date(), attempts: [])
        commit(next)
    }

    func record(landing: ServeLanding, from court: ServiceCourt, aimingAt target: ServeTarget) {
        guard var session = activeSession else { return }
        session.attempts.append(ServeAttempt(id: UUID(), recordedAt: Date(), serviceCourt: court,
                                           intendedTarget: target, landingResult: landing))
        var next = archive
        next.activeSession = session
        commit(next)
    }

    func undoLastServe() {
        guard var session = activeSession, !session.attempts.isEmpty else { return }
        session.attempts.removeLast()
        var next = archive
        next.activeSession = session
        commit(next)
    }

    func finishSession() {
        guard var session = activeSession else { return }
        var next = archive
        if !session.attempts.isEmpty {
            session.finishedAt = Date()
            next.completedSessions.insert(session, at: 0)
        }
        next.activeSession = nil
        commit(next)
    }

    func removeSession(_ sessionID: UUID) {
        var next = archive
        next.completedSessions.removeAll { $0.id == sessionID }
        commit(next)
    }

    func exportSession(_ session: ServePracticeSession) -> URL? {
        // Export stable, documented English column names for spreadsheet interoperability.
        let dates = ISO8601DateFormatter()
        var lines = ["recorded_at_utc,service_court,intended_target,landing_result"]
        lines += session.attempts.map {
            "\(dates.string(from: $0.recordedAt)),\($0.serviceCourt.rawValue),\($0.intendedTarget.rawValue),\($0.landingResult.rawValue)"
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ServeExports", isDirectory: true)
        let url = folder.appendingPathComponent("serve-practice-\(session.id.uuidString).csv")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
            return url
        } catch { storageMessage = "The practice export could not be created. Please try again."; return nil }
    }

    private func commit(_ next: ServeJournalArchive) {
        guard storageReadable else { return }
        do {
            let data = try JSONEncoder().encode(next)
            try data.write(to: archiveURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            archive = next
            storageMessage = nil
        } catch { storageMessage = "This change could not be saved. Please try again." }
    }
}

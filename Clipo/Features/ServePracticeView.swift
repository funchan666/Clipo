import SwiftUI

struct ServePracticeEntry: View {
    let openJournal: () -> Void
    var body: some View {
        Button(action: openJournal) {
            VStack(alignment: .leading, spacing: 6) {
                LocalizedText("Serve practice").font(.court(.title3, weight: .semibold))
                LocalizedText("Pick a target. Track your placement.").font(.court(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(ClipoStyle.paper)
            .padding(20).frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
            .background {
                Image("ServePracticeHero").resizable().scaledToFill()
                    .overlay(ClipoStyle.background.opacity(0.30))
            }.clipped().contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("practice.openJournal")
    }
}

struct ServePracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @StateObject private var journal = ServePracticeJournal()
    @State private var serviceCourt = ServiceCourt.deuce
    @State private var intendedTarget = ServeTarget.wide
    @State private var showingHistory = false
    @State private var selectedSession: ServePracticeSession?
    @State private var pendingRemoval: ServePracticeSession?
    @State private var sharedExport: SharedFile?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Serve practice") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image("ServePracticeHero").resizable().scaledToFit().accessibilityHidden(true)
                    CourtFilter(values: ["Practice", "Sessions"], selected: showingHistory ? "Sessions" : "Practice") {
                        showingHistory = $0 == "Sessions"
                    }
                    if let message = journal.storageMessage { ErrorNote(message: message) }
                    if showingHistory { history } else { practice }
                }.clipoPage().frame(maxWidth: 660).frame(maxWidth: .infinity)
            }
        }.foregroundStyle(ClipoStyle.paper).clipoScreenBackground()
            .sheet(item: $selectedSession) { session in
                VStack(spacing: 0) {
                    SheetHeading(title: "Session results") { selectedSession = nil }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(session.startedAt, format: .dateTime.year().month().day().hour().minute().locale(locale))
                                .font(.court(.subheadline))
                            summary(session)
                            placementBreakdown(session)
                            ActionButton(title: "Export session CSV", primary: false) {
                                if let url = journal.exportSession(session) { sharedExport = SharedFile(url: url) }
                            }
                            if let message = journal.storageMessage { ErrorNote(message: message) }
                            Button { pendingRemoval = session } label: { LocalizedText("Delete session") }
                                .buttonStyle(CompactActionStyle())
                        }.clipoPage()
                    }
                }.clipoScreenBackground().foregroundStyle(ClipoStyle.paper)
                    .sheet(item: $sharedExport) { ShareSheet(items: [$0.url]) }
                    .fullScreenCover(item: $pendingRemoval) { session in
                        AccountDecisionDialog(title: "Delete session?", message: "This removes this practice session and its serve records.",
                            confirmTitle: "Delete session", destructive: true,
                            cancel: { pendingRemoval = nil }) {
                                journal.removeSession(session.id)
                                pendingRemoval = nil
                                if !journal.completedSessions.contains(where: { $0.id == session.id }) { selectedSession = nil }
                            }.presentationBackground(.clear)
                    }
            }
    }

    @ViewBuilder private var practice: some View {
        if let session = journal.activeSession {
            LocalizedText("Choose your serving side and intended target before recording each serve.")
                .font(.court(.subheadline)).foregroundStyle(ClipoStyle.secondary)
            CourtFilter(values: ServiceCourt.allCases.map(\.label), selected: serviceCourt.label) { label in
                if let court = ServiceCourt.allCases.first(where: { $0.label == label }) { serviceCourt = court }
            }
            CourtFilter(values: ServeTarget.allCases.map(\.label), selected: intendedTarget.label) { label in
                if let target = ServeTarget.allCases.first(where: { $0.label == label }) { intendedTarget = target }
            }
            summary(session)
            LocalizedText("Record the landing").font(.court(.headline))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(ServeLanding.allCases) { landing in
                    ActionButton(title: landing.label, primary: landing == .targetHit) {
                        journal.record(landing: landing, from: serviceCourt, aimingAt: intendedTarget)
                    }.disabled(!journal.available)
                }
            }
            HStack {
                Button { journal.undoLastServe() } label: { LocalizedText("Undo last serve") }
                    .buttonStyle(CompactActionStyle()).disabled(session.attempts.isEmpty)
                Spacer(minLength: 0)
            }
            ActionButton(title: "Finish session", primary: false) {
                journal.finishSession()
                if journal.activeSession == nil { showingHistory = true }
            }
        } else {
            LocalizedText("Build a more reliable serve.").font(.court(.title2, editorial: true))
            LocalizedText("Record where each serve lands. Compare your targets across both service courts.")
                .font(.court(.subheadline)).foregroundStyle(ClipoStyle.secondary)
            ActionButton(title: "Start a practice session") { journal.beginSession() }.disabled(!journal.available)
        }
        LocalizedText("Record between serves, with your phone safely off the court. Results are based on your entries, not automatic video analysis.")
            .font(.court(.footnote)).foregroundStyle(ClipoStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var history: some View {
        if journal.completedSessions.isEmpty {
            LocalizedText("Your next session starts here.").font(.court(.headline))
            LocalizedText("Finished sessions appear here with their placement results.")
                .font(.court(.subheadline)).foregroundStyle(ClipoStyle.secondary)
        } else {
            ForEach(journal.completedSessions) { session in
                Button { selectedSession = session } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(session.startedAt, format: .dateTime.month().day().hour().minute().locale(locale))
                            .font(.court(.headline))
                        summary(session)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background { OriginalSurface(tone: .pine) }.contentShape(Rectangle())
                }.buttonStyle(PressStyle())
            }
        }
    }

    private func summary(_ session: ServePracticeSession) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) { metrics(session) }
            VStack(alignment: .leading, spacing: 10) { metrics(session) }
        }.accessibilityElement(children: .combine)
    }

    @ViewBuilder private func metrics(_ session: ServePracticeSession) -> some View {
        metric("Serves", value: session.attempts.count.formatted(.number.locale(locale)))
        metric("In service box", value: session.inCount.formatted(.number.locale(locale)))
        metric("Target accuracy", value: session.attempts.isEmpty ? "—" :
            (Double(session.targetCount) / Double(session.attempts.count)).formatted(.percent.precision(.fractionLength(0)).locale(locale)))
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: value).font(.court(.title2, weight: .semibold)).monospacedDigit()
            LocalizedText(title).font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func placementBreakdown(_ session: ServePracticeSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(ServiceCourt.allCases) { court in
                LocalizedText(court.label).font(.court(.headline))
                ForEach(ServeTarget.allCases) { target in
                    let serves = session.attempts.filter { $0.serviceCourt == court && $0.intendedTarget == target }
                    let hits = serves.filter { $0.landingResult == .targetHit }.count
                    HStack {
                        LocalizedText(target.label)
                        Spacer(minLength: 8)
                        Text(verbatim: serves.isEmpty ? "—" : "\(hits) / \(serves.count)").monospacedDigit()
                    }.font(.court(.subheadline))
                }
            }
            LocalizedText("Target hits / serves attempted. A target hit also counts as a serve in the service box.")
                .font(.court(.footnote)).foregroundStyle(ClipoStyle.secondary)
        }
    }
}

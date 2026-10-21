import SwiftUI

// Bundled editorial content. Reading never calls video, quota or advertising APIs.
private struct TennisNote: Identifiable {
    struct Section {
        let title: String
        let body: String
        init(_ title: String, _ body: String) { self.title = title; self.body = body }
    }
    struct Source {
        let title: String
        let address: String
    }
    let id: String
    let category: String
    let title: String
    let summary: String
    let artwork: TennisArtwork.Kind
    let sections: [Section]
    let takeaway: String
    let sources: [Source]

    var cover: CourtArtwork.Subject {
        switch id {
        case "forehand": .forehand
        case "backhand": .backhand
        case "serve": .serve
        case "scoring": .scoring
        default: .majors
        }
    }
    var shortTitle: String {
        switch id {
        case "forehand": "Forehand"
        case "backhand": "Backhand"
        case "serve": "Serve"
        case "scoring": "Scoring"
        default: "Majors"
        }
    }

    // Original summaries, checked against the linked primary sources on 2026-10-20.
    // Keep these evergreen: no live rankings, event dates, results or prize money.
    static let all: [TennisNote] = [
        TennisNote(
            id: "forehand", category: "Technique", title: "Find your forehand.",
            summary: "Start with contact and control, then build your swing.",
            artwork: .racket,
            sections: [
                .init("Turn together",
                      "Prepare by turning your upper body and hips together, rather than pulling only the racket behind you. This gives the swing a connected starting point."),
                .init("Leave room for contact",
                      "For a right-handed forehand, meet the ball slightly in front and to your right; reverse the side if you play left-handed. Small adjusting steps help you avoid getting crowded by the ball."),
                .init("Control before speed",
                      "The direction of the racket face at contact strongly affects where the ball goes. Begin with a comfortable swing and aim to keep the ball in play. Add pace and spin as your contact becomes more reliable.")
            ],
            takeaway: "When reviewing your footage, pause at contact: is there space between the ball and your body?",
            sources: [
                .init(title: "USTA · Forehand basics", address: "https://www.usta.com/en/home/improve/tips-and-instruction/national/learning-the-basics--forehand.html"),
                .init(title: "USTA · Preparing the forehand", address: "https://www.usta.com/en/home/improve/tips-and-instruction/national/improve-your-tennis-game--get-your-forehand-flowing.html")
            ]),
        TennisNote(
            id: "backhand", category: "Technique", title: "Get to know your backhand.",
            summary: "One hand or two, a steady contact point comes first.",
            artwork: .racket,
            sections: [
                .init("The other side",
                      "A right-handed player's backhand is usually struck on the left side of the body, slightly in front. A left-handed player reverses the sides. Give yourself room instead of letting the ball arrive too close."),
                .init("One hand or two?",
                      "Both styles are valid. On a typical two-handed backhand, the dominant hand sits lower on the handle and the other hand above it. Choose a comfortable setup that lets you control the racket face."),
                .init("Build a repeatable rally",
                      "A harder swing is not automatically a better shot. Start at a pace that keeps the ball inside the court. Keep your grip relaxed enough to avoid squeezing the handle tightly throughout the swing.")
            ],
            takeaway: "Watch a few backhands in a row. Notice contact spacing and balance before judging power.",
            sources: [.init(title: "USTA · Backhand basics", address: "https://www.usta.com/en/home/improve/tips-and-instruction/national/learning-the-basics--backhand.html")]),
        TennisNote(
            id: "serve", category: "Technique", title: "A serve starts with the toss.",
            summary: "Give your swing a consistent ball to meet.",
            artwork: .lesson,
            sections: [
                .init("Make the toss familiar",
                      "The tossing arm is usually your non-dominant arm, so the movement can feel unfamiliar. Practise the toss on its own before combining it with the racket swing."),
                .init("Let the ball meet your motion",
                      "An inconsistent toss makes even a well-practised swing difficult to repeat. Work on placing the ball where your motion can reach it comfortably, rather than changing your swing to chase each toss."),
                .init("Start with a shorter motion",
                      "Beginners can use an abbreviated service motion while learning how contact feels. A fuller throwing-style motion can develop gradually. A coach can help you adapt the movement to your grip, coordination and experience.")
            ],
            takeaway: "Review the toss first. Does it arrive in a similar place on successive serves?",
            sources: [.init(title: "USTA · Serving basics", address: "https://www.usta.com/en/home/improve/tips-and-instruction/national/learning-the-basics--serve.html")]),
        TennisNote(
            id: "scoring", category: "Rules", title: "Love, deuce, advantage.",
            summary: "A short guide to following the score.",
            artwork: .notebook,
            sections: [
                .init("Points make a game",
                      "In standard advantage scoring, zero is called love. The next points are 15, 30 and 40. A player wins a game with at least four points and a lead of two. The server's score is announced first."),
                .init("What happens at 40–40?",
                      "This is deuce. Winning the next point gives a player advantage. Win the following point to take the game; lose it and the score returns to deuce. Some formats use a deciding point instead, called no-ad scoring."),
                .init("Games make sets",
                      "A common set format is first to six games with a two-game lead, with a tiebreak at 6–6. A match is decided by sets. Tiebreak targets and match formats vary, so check the rules of the event you are watching.")
            ],
            takeaway: "If the server has won two points and the receiver one, the score is 30–15.",
            sources: [.init(title: "USTA · Scoring explained", address: "https://www.usta.com/en/home/improve/tips-and-instruction/national/tennis-scoring-rules.html")]),
        TennisNote(
            id: "majors", category: "Majors", title: "Four majors. Three surfaces.",
            summary: "Meet the Australian Open, Roland-Garros, Wimbledon and US Open.",
            artwork: .bag,
            sections: [
                .init("Australian Open · Melbourne",
                      "The first major of the calendar year is held at Melbourne Park in Australia. It is played on hard courts; the tournament moved away from grass when it moved to this venue in 1988."),
                .init("Roland-Garros · Paris",
                      "Also called the French Open, this major is played on red clay. The court's familiar colour comes from a fine layer of crushed brick over its underlying structure."),
                .init("Wimbledon · London",
                      "The Championships are held at the All England Club. Wimbledon is the only one of the four majors still played on grass."),
                .init("US Open · New York",
                      "The US Open is held at the USTA Billie Jean King National Tennis Center in Flushing Meadows. It has used hard courts since 1978, after earlier periods on grass and clay.")
            ],
            takeaway: "Two hard-court majors, one clay-court major and one grass-court major.",
            sources: [.init(title: "ITF · The Grand Slam tournaments", address: "https://www.itftennis.com/en/tours/grand-slam-tournaments/")])
    ]
}

// Shared entry point for Home and the practice-tools tab.
struct TennisGuideEntry: View {
    var compact = false
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 18) {
                CourtArtwork(subject: .serve).frame(width: compact ? 72 : 94, height: compact ? 88 : 116)
                VStack(alignment: .leading, spacing: 8) {
                    LocalizedText("Tennis field notes").font(.court(.headline))
                        .foregroundStyle(ClipoStyle.paper)
                    LocalizedText("\(TennisNote.all.count) short reads · Available offline")
                        .font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Glyph(symbol: .back, size: 12, tint: ClipoStyle.accent)
                    .rotationEffect(.degrees(180)).frame(width: 20)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background { OriginalSurface(tone: .pine) }
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("tennisGuide.open")
    }
}

struct TennisGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var category = "All"
    private let categories = ["All", "Technique", "Rules", "Majors"]
    private var notes: [TennisNote] {
        TennisNote.all.filter { category == "All" || $0.category == category }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetHeading(title: "Tennis field notes") { dismiss() }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        CourtFilter(values: categories, selected: category) { category = $0 }
                        if let first = notes.first {
                            NavigationLink(value: first.id) {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 20) {
                                        CourtArtwork(subject: first.cover).frame(width: 148, height: 148)
                                        VStack(alignment: .leading, spacing: 14) {
                                            LocalizedText(first.shortTitle).font(.court(.title2, weight: .semibold))
                                                .fixedSize(horizontal: false, vertical: true)
                                            Glyph(symbol: .back, size: 16, tint: ClipoStyle.ink)
                                                .rotationEffect(.degrees(180))
                                        }.frame(minWidth: 112, maxWidth: .infinity, alignment: .leading)
                                    }
                                    VStack(alignment: .leading, spacing: 14) {
                                        CourtArtwork(subject: first.cover).aspectRatio(1.4, contentMode: .fit)
                                        LocalizedText(first.shortTitle).font(.court(.title2, weight: .semibold))
                                    }
                                }.padding(14).foregroundStyle(ClipoStyle.ink)
                                    .background { OriginalSurface(tone: .ivory) }
                                    .contentShape(Rectangle())
                            }.buttonStyle(PressStyle()).accessibilityIdentifier("tennisGuide.\(first.id)")
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 140), spacing: 16)], alignment: .leading, spacing: 22) {
                            ForEach(Array(notes.dropFirst())) { note in
                                NavigationLink(value: note.id) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        CourtArtwork(subject: note.cover).aspectRatio(1, contentMode: .fit)
                                        HStack(alignment: .top, spacing: 8) {
                                            LocalizedText(note.shortTitle).font(.court(.headline))
                                                .fixedSize(horizontal: false, vertical: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Glyph(symbol: .back, size: 10, tint: ClipoStyle.accent)
                                                .rotationEffect(.degrees(180)).padding(.top, 3)
                                        }
                                    }.foregroundStyle(ClipoStyle.paper).contentShape(Rectangle())
                                }.buttonStyle(PressStyle()).accessibilityIdentifier("tennisGuide.\(note.id)")
                            }
                        }
                    }.clipoPage()
                }
            }.clipoScreenBackground().foregroundStyle(ClipoStyle.paper)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { id in
                    if let note = TennisNote.all.first(where: { $0.id == id }) {
                        TennisNoteReader(note: note)
                    }
                }
        }
    }
}

private struct TennisNoteReader: View {
    let note: TennisNote
    @Environment(\.dismiss) private var dismiss
    @State private var source: PolicyDocument?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconButton(symbol: .back, label: "Back to field notes") { dismiss() }
                LocalizedText(note.category).font(.court(.subheadline, weight: .semibold))
                    .foregroundStyle(ClipoStyle.secondary)
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    CourtArtwork(subject: note.cover).aspectRatio(1, contentMode: .fit).frame(maxWidth: 360)
                    VStack(alignment: .leading, spacing: 14) {
                        LocalizedText(note.title)
                            .font(.court(.title2, weight: .semibold))
                            .foregroundStyle(ClipoStyle.paper).accessibilityAddTraits(.isHeader)
                    }
                    ForEach(note.sections.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            LocalizedText(note.sections[index].title).font(.court(.headline))
                                .accessibilityAddTraits(.isHeader)
                            LocalizedText(note.sections[index].body).font(.court(.body)).lineSpacing(5)
                                .foregroundStyle(ClipoStyle.paper.opacity(0.9))
                                .textSelection(.enabled)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        LocalizedText("ONE THING TO REMEMBER").font(.court(.caption2, weight: .bold)).tracking(1.5)
                        LocalizedText(note.takeaway).font(.court(.body, weight: .medium)).lineSpacing(3)
                    }.foregroundStyle(ClipoStyle.ink)
                        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background { OriginalSurface(tone: .ivory) }
                    VStack(alignment: .leading, spacing: 6) {
                        LocalizedText("Further reading").font(.court(.headline))
                        LocalizedText("Official sources · Opens online")
                            .font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
                        ForEach(note.sources, id: \.address) { reference in
                            if let url = URL(string: reference.address) {
                                Button {
                                    source = PolicyDocument(title: reference.title, url: url)
                                } label: {
                                    LocalizedText(reference.title).font(.court(.subheadline, weight: .medium))
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                }.foregroundStyle(ClipoStyle.accent).buttonStyle(PressStyle())
                            }
                        }
                    }
                }.clipoPage()
            }
        }.clipoScreenBackground().foregroundStyle(ClipoStyle.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $source) { PolicyBrowser(document: $0) }
    }
}

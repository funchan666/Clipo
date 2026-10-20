import SwiftUI
import UIKit

// Native layout and typography; every pictorial mark comes from the original raster atlas.
enum ClipoStyle {
    static let background = Color(red: 0.035, green: 0.09, blue: 0.075)
    static let surface = Color(red: 0.065, green: 0.16, blue: 0.13)
    static let raised = Color(red: 0.12, green: 0.23, blue: 0.19)
    static let accent = Color(red: 0.847, green: 1, blue: 0.384)
    static let ink = Color(red: 0.055, green: 0.07, blue: 0.04)
    static let secondary = Color(red: 0.65, green: 0.69, blue: 0.65)
    static let paper = Color(red: 0.949, green: 0.941, blue: 0.867)
    static let paperSecondary = Color(red: 0.32, green: 0.37, blue: 0.29)
    static let line = Color.white.opacity(0.10)
    static let danger = Color(red: 1, green: 0.64, blue: 0.59)
}

// Display-only cropping of the original four-cell tennis illustration.
struct TennisArtwork: View {
    enum Kind: Int { case racket, lesson, bag, notebook }
    let kind: Kind
    var height: CGFloat = 160
    var body: some View {
        GeometryReader { geometry in
            Image("ClipoTennisKit").resizable().interpolation(.high)
                .frame(width: geometry.size.width * 2, height: geometry.size.height * 2)
                .offset(x: -CGFloat(kind.rawValue % 2) * geometry.size.width,
                        y: -CGFloat(kind.rawValue / 2) * geometry.size.height)
                .allowsHitTesting(false)
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(width: height, height: height).clipped()
        .frame(maxWidth: .infinity).accessibilityHidden(true)
    }
}

struct TennisCourtBanner: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedText("ON COURT · ON REPEAT")
                .font(.caption2.weight(.bold)).tracking(2)
                .foregroundStyle(ClipoStyle.accent)
            LocalizedText("A better game\nstarts here.")
                .font(.system(.largeTitle, design: .serif, weight: .medium))
                .foregroundStyle(ClipoStyle.paper)
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText("Watch. Practise. Repeat.")
                .font(.subheadline).foregroundStyle(ClipoStyle.paper)
        }
        .padding(24).frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
        .background {
            // Foreground text remains native and resizes independently of the artwork.
            Image("ClipoTennisCourt").resizable().scaledToFill()
                .overlay(ClipoStyle.background.opacity(typeSize.isAccessibilitySize ? 0.65 : 0.35))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}
enum ClipoGlyph: Int {
    case home, feed, edit, library, link, search, bookmark, download
    case play, pause, close, back, sound, mute, folder, settings
}
struct Glyph: View {
    @Environment(\.layoutDirection) private var direction
    let symbol: ClipoGlyph
    var size: CGFloat = 25
    var tint: Color = .white
    private var cellOrigin: CGPoint {
        if symbol == .link {
            // In the 1254px atlas, the link's visible bounds are (82, 400)–(288, 601).
            // Center that artwork in its viewport instead of assuming an even grid.
            let cellSide: CGFloat = 313.5
            return CGPoint(x: 185 / cellSide - 0.5, y: 500.5 / cellSide - 0.5)
        }
        return CGPoint(x: CGFloat(symbol.rawValue % 4), y: CGFloat(symbol.rawValue / 4))
    }
    var body: some View {
        // Cell extraction is display-only: the source artwork is never redrawn in code.
        GeometryReader { geometry in
            Image("ClipoGlyphAtlas").resizable().interpolation(.high).colorMultiply(tint)
                .frame(width: geometry.size.width * 4, height: geometry.size.height * 4)
                .offset(x: -cellOrigin.x * geometry.size.width,
                        y: -cellOrigin.y * geometry.size.height)
                // The enlarged atlas is artwork, never an independent touch target.
                .allowsHitTesting(false)
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(width: size * 1.65, height: size * 1.65)
        .clipped().contentShape(.interaction, Rectangle())
        .blendMode(.screen)
        .scaleEffect(x: symbol == .back && direction == .rightToLeft ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }
}
struct IconButton: View {
    let symbol: ClipoGlyph
    let label: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Glyph(symbol: symbol).allowsHitTesting(false).frame(width: 48, height: 48)
                .background(selected ? ClipoStyle.raised : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(.interaction, Rectangle())
        }.buttonStyle(PressStyle()).accessibilityLabel(LocalizedStringKey(label))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct PressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(!isEnabled ? 0.6 : (configuration.isPressed ? 0.65 : 1))
    }
}
struct ActionButton: View {
    let title: String
    var primary = true
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            LocalizedText(busy ? "Please wait…" : title).font(.body.weight(.semibold))
                .multilineTextAlignment(.center).padding(.horizontal, 16).padding(.vertical, 14)
                .foregroundStyle(primary ? ClipoStyle.ink : Color.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background { OriginalSurface(tone: primary ? .accent : .pine) }
                .contentShape(.interaction, Rectangle())
        }.buttonStyle(PressStyle()).disabled(busy)
    }
}
struct MessagePanel: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LocalizedText(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
            LocalizedText(message).font(.subheadline).foregroundStyle(ClipoStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action { ActionButton(title: actionTitle, primary: false, action: action) }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
struct ErrorNote: View {
    @Environment(\.locale) private var locale
    let message: String
    var body: some View {
        LocalizedText(message).font(.subheadline).foregroundStyle(ClipoStyle.danger)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            .accessibilityLabel(Text(verbatim: L10n.display("Error: \(message)", language: AppLanguage.from(locale))))
    }
}
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.body).foregroundStyle(.white).padding(16)
            .background(ClipoStyle.raised, in: RoundedRectangle(cornerRadius: 14))
            .tint(ClipoStyle.accent)
    }
}
extension View {
    func clipoField() -> some View { modifier(FieldStyle()) }
    // Extend visual surfaces to every container edge, while preserving keyboard avoidance
    // and the foreground's safe area for interactive controls.
    func clipoScreenBackground(_ color: Color = ClipoStyle.background) -> some View {
        background { color.ignoresSafeArea(.container, edges: .all) }
    }
    // A readable column follows the available container without resetting page state.
    func clipoPage() -> some View {
        padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 28)
            .frame(maxWidth: 680).frame(maxWidth: .infinity, alignment: .top)
    }
}
struct MediaCover: View {
    let url: URL?
    var folder = false
    var body: some View {
        ClipoStyle.raised.overlay {
            GeometryReader { geometry in
                Group {
                    if folder { Glyph(symbol: .folder, size: 30) }
                    else if let url {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Glyph(symbol: .feed, size: 30) }
                        }
                    } else { Glyph(symbol: .feed, size: 30) }
                }.frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        }.clipped()
    }
}
struct SheetHeading: View {
    let title: String
    var close: () -> Void
    var body: some View {
        HStack {
            LocalizedText(title).font(.title3.weight(.bold)).lineLimit(2)
            Spacer()
            IconButton(symbol: .close, label: "Close", action: close)
        }.padding(.horizontal, 20).padding(.top, 12)
    }
}

struct SectionLabel: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                LocalizedText(title).font(.headline)
                Spacer(minLength: 12)
                if let detail { LocalizedText(detail).font(.caption).foregroundStyle(ClipoStyle.secondary) }
            }
            VStack(alignment: .leading, spacing: 6) {
                LocalizedText(title).font(.headline)
                if let detail { LocalizedText(detail).font(.caption).foregroundStyle(ClipoStyle.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Original raster artwork. Its layout never participates in navigation hit testing.
struct ClipoIllustration: View {
    let name: String
    var height: CGFloat = 180
    var body: some View {
        Image(name)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct FeatureRow: View {
    let symbol: ClipoGlyph
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 16) {
            Glyph(symbol: symbol, size: 22)
                .frame(width: 48, height: 48)
                .background(ClipoStyle.raised, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                LocalizedText(detail).font(.caption).foregroundStyle(ClipoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// These components only display/crop original generated bitmap artwork.
// Native code supplies layout, accessible labels and touch handling, never drawn artwork.
struct CourtArtwork: View {
    enum Subject: Int { case forehand, backhand, serve, scoring, majors, review, speed, frame, audio }
    let subject: Subject
    // Measured boundaries in the generated 1254px atlas; row heights are not identical.
    private var crop: CGRect {
        let rows: [CGFloat] = [0, 418, 808, 1254]
        let row = subject.rawValue / 3
        return CGRect(x: CGFloat(subject.rawValue % 3) * 418 + 1,
                      y: rows[row] + 1, width: 416, height: rows[row + 1] - rows[row] - 2)
    }
    var body: some View {
        GeometryReader { geometry in
            let scale = max(geometry.size.width / crop.width, geometry.size.height / crop.height)
            Image("ClipoCourtEditorial").resizable().interpolation(.high)
                .frame(width: 1254 * scale, height: 1254 * scale)
                .offset(x: -crop.minX * scale + (geometry.size.width - crop.width * scale) / 2,
                        y: -crop.minY * scale + (geometry.size.height - crop.height * scale) / 2)
        }.environment(\.layoutDirection, .leftToRight).clipped()
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct OriginalSurface: View {
    enum Tone: Int { case accent, pine, ivory, sage }
    let tone: Tone
    // Raster extraction only. No paths, drawing contexts or generated shapes.
    // Cap insets preserve the artist's corners on both short chips and large panels.
    private static let surfaces: [UIImage] = {
        guard let source = UIImage(named: "ClipoCourtControls")?.cgImage else { return [] }
        let width = CGFloat(source.width), rowHeight = CGFloat(source.height) / 4
        return (0..<4).compactMap { row in
            let rect = CGRect(x: 6, y: CGFloat(row) * rowHeight + 6, width: width - 12, height: rowHeight - 12)
            guard let tile = source.cropping(to: rect) else { return nil }
            return UIImage(cgImage: tile, scale: 3, orientation: .up)
        }
    }()
    var body: some View {
        if Self.surfaces.indices.contains(tone.rawValue) {
            Image(uiImage: Self.surfaces[tone.rawValue])
                .resizable(capInsets: EdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22), resizingMode: .stretch)
                .environment(\.layoutDirection, .leftToRight)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

struct CourtFilter: View {
    let values: [String]
    let selected: String
    let select: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button { select(value) } label: {
                        LocalizedText(value).font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 22).padding(.vertical, 14)
                            .frame(minHeight: 48)
                            .foregroundStyle(selected == value ? ClipoStyle.ink : ClipoStyle.paper)
                            .background { OriginalSurface(tone: selected == value ? .accent : .pine) }
                            .contentShape(Rectangle())
                    }.buttonStyle(PressStyle())
                        .accessibilityAddTraits(selected == value ? .isSelected : [])
                }
            }
        }
    }
}

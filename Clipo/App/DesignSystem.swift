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
    // The bag crosses the atlas midpoint. Exclude its stray edge from the notebook tile.
    private static let notebook: UIImage? = {
        guard let source = UIImage(named: "ClipoTennisKit")?.cgImage,
              let tile = source.cropping(to: CGRect(
                x: CGFloat(source.width) * 0.53, y: CGFloat(source.height) * 0.5,
                width: CGFloat(source.width) * 0.47, height: CGFloat(source.height) * 0.5
              )) else { return nil }
        return UIImage(cgImage: tile)
    }()
    var body: some View {
        GeometryReader { geometry in
            if kind == .notebook, let notebook = Self.notebook {
                Image(uiImage: notebook).resizable().interpolation(.high).scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
            } else {
            Image("ClipoTennisKit").resizable().interpolation(.high)
                .frame(width: geometry.size.width * 2, height: geometry.size.height * 2)
                .offset(x: -CGFloat(kind.rawValue % 2) * geometry.size.width,
                        y: -CGFloat(kind.rawValue / 2) * geometry.size.height)
                .allowsHitTesting(false)
            }
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
                .font(.court(.caption2, weight: .bold)).tracking(2)
                .foregroundStyle(ClipoStyle.accent)
            LocalizedText("A better game\nstarts here.")
                .font(.court(.title, editorial: true))
                .foregroundStyle(ClipoStyle.paper)
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText("Watch. Practise. Repeat.")
                .font(.court(.subheadline)).foregroundStyle(ClipoStyle.paper)
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
enum ClipoGlyph: Int, CaseIterable {
    case home, feed, edit, library, link, search, bookmark, download
    case play, pause, close, back, sound, mute, folder, settings
}
struct Glyph: View {
    @Environment(\.layoutDirection) private var direction
    let symbol: ClipoGlyph
    var size: CGFloat = 25
    var tint: Color = .white
    private static let tiles: [ClipoGlyph: UIImage] = {
        guard let source = UIImage(named: "ClipoGlyphAtlas")?.cgImage else { return [:] }
        let side = CGFloat(source.width) / 4
        return Dictionary(uniqueKeysWithValues: ClipoGlyph.allCases.compactMap { symbol -> (ClipoGlyph, UIImage)? in
            let origin = symbol == .link
                ? CGPoint(x: 185.0 / 1254 * CGFloat(source.width) - side / 2,
                          y: 500.5 / 1254 * CGFloat(source.height) - side / 2)
                : CGPoint(x: CGFloat(symbol.rawValue % 4) * side, y: CGFloat(symbol.rawValue / 4) * side)
            guard let tile = source.cropping(to: CGRect(origin: origin, size: CGSize(width: side, height: side)).integral) else { return nil }
            return (symbol, UIImage(cgImage: tile))
        })
    }()
    var body: some View {
        OriginalSymbolMask(image: Self.tiles[symbol], tint: tint)
            .frame(width: size * 1.65, height: size * 1.65)
            .scaleEffect(x: symbol == .back && direction == .rightToLeft ? -1 : 1, y: 1)
            .accessibilityHidden(true)
    }
}

// Display the existing white-on-black artwork as an isolated opacity mask.
// Unlike screen blending, its black pixels never depend on the video beneath it.
// This is raster display/tinting only; no replacement artwork is drawn.
struct OriginalSymbolMask: View {
    let image: UIImage?
    var tint: Color = .white
    var body: some View {
        if let image {
            tint.mask {
                Image(uiImage: image).resizable().interpolation(.high)
                    .scaledToFit().luminanceToAlpha()
            }.environment(\.layoutDirection, .leftToRight)
                .allowsHitTesting(false)
        }
    }
}

struct IconButton: View {
    let symbol: ClipoGlyph
    let label: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Glyph(symbol: symbol, size: 19).allowsHitTesting(false).frame(width: 44, height: 44)
                .background {
                    if selected { OriginalSurface(tone: .pine) }
                }
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
// Compact controls retain their full localized label; enclosing layouts can scroll
// or use ViewThatFits instead of splitting words into multiple lines.
struct CompactActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.court(.footnote, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .foregroundStyle(ClipoStyle.paper)
            .background { OriginalSurface(tone: .pine) }
            .contentShape(.interaction, Rectangle())
            .opacity(!isEnabled ? 0.6 : (configuration.isPressed ? 0.65 : 1))
    }
}
struct ActionButton: View {
    let title: String
    var primary = true
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            LocalizedText(busy ? "Please wait…" : title).font(.court(.subheadline, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.75)
                .multilineTextAlignment(.center).padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(primary ? ClipoStyle.ink : Color.white)
                .frame(maxWidth: .infinity, minHeight: 48)
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
            LocalizedText(title).font(.court(.headline)).foregroundStyle(.white)
            LocalizedText(message).font(.court(.subheadline)).foregroundStyle(ClipoStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action { ActionButton(title: actionTitle, primary: false, action: action) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
struct ErrorNote: View {
    @Environment(\.locale) private var locale
    let message: String
    var body: some View {
        LocalizedText(message).font(.court(.subheadline)).foregroundStyle(ClipoStyle.danger)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            .accessibilityLabel(Text(verbatim: L10n.display("Error: \(message)", language: AppLanguage.from(locale))))
    }
}
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.court(.subheadline)).foregroundStyle(.white).padding(14)
            .background(ClipoStyle.raised, in: RoundedRectangle(cornerRadius: 14))
            .tint(ClipoStyle.accent)
    }
}
// Measure in the owning screen, so scrolling, keyboard avoidance and resizing
// keep the input exclusion region aligned. No global window or focus broadcast.
private struct KeyboardInputBounds: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $0.union($1) })
    }
}
private struct OutsideInputTap: ViewModifier {
    let focus: FocusState<Bool>.Binding
    let scope: String
    @State private var inputBounds: CGRect?
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle()) // Hit area only, no visible artwork.
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named(scope)).onEnded { tap in
                guard focus.wrappedValue, let inputBounds, !inputBounds.contains(tap.location) else { return }
                focus.wrappedValue = false
            })
            .onPreferenceChange(KeyboardInputBounds.self) { inputBounds = $0[scope] }
            .coordinateSpace(name: scope)
    }
}

extension View {
    func keyboardInputRegion(_ scope: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: KeyboardInputBounds.self,
                                       value: [scope: geometry.frame(in: .named(scope))])
            }.allowsHitTesting(false)
        }
    }
    func dismissKeyboardOnOutsideTap(_ focus: FocusState<Bool>.Binding, scope: String) -> some View {
        modifier(OutsideInputTap(focus: focus, scope: scope))
    }
    func clipoField() -> some View { modifier(FieldStyle()) }
    // Extend visual surfaces to every container edge, while preserving keyboard avoidance
    // and the foreground's safe area for interactive controls.
    func clipoScreenBackground(_ color: Color = ClipoStyle.background) -> some View {
        background { color.ignoresSafeArea(.container, edges: .all) }
    }
    // A readable column follows the available container without resetting page state.
    func clipoPage() -> some View {
        padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
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
            LocalizedText(title).font(.court(.headline)).lineLimit(2)
            Spacer()
            IconButton(symbol: .close, label: "Close", action: close)
        }.padding(.horizontal, 20).padding(.top, 8)
    }
}

struct SectionLabel: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                LocalizedText(title).font(.court(.headline))
                Spacer(minLength: 12)
                if let detail { LocalizedText(detail).font(.court(.caption)).foregroundStyle(ClipoStyle.secondary) }
            }
            VStack(alignment: .leading, spacing: 6) {
                LocalizedText(title).font(.court(.headline))
                if let detail { LocalizedText(detail).font(.court(.caption)).foregroundStyle(ClipoStyle.secondary) }
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
                LocalizedText(title).font(.court(.subheadline, weight: .semibold)).foregroundStyle(.white)
                LocalizedText(detail).font(.court(.caption)).foregroundStyle(ClipoStyle.secondary)
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
        // The original is 2172 × 724, but its painted rows are not equal quarters.
        // Equal-row slicing cut through the accent's lower rim and included the
        // next row beneath the ivory button. Keep each complete painted border.
        let boundaries: [CGFloat] = [13, 185, 360, 535, 708]
        let scaleX = CGFloat(source.width) / 2172
        let scaleY = CGFloat(source.height) / 724
        return (0..<4).compactMap { row in
            let rect = CGRect(x: 12 * scaleX, y: boundaries[row] * scaleY,
                              width: 2148 * scaleX,
                              height: (boundaries[row + 1] - boundaries[row]) * scaleY).integral
            guard let tile = source.cropping(to: rect) else { return nil }
            return UIImage(cgImage: tile, scale: 3, orientation: .up)
        }
    }()
    var body: some View {
        if Self.surfaces.indices.contains(tone.rawValue) {
            Image(uiImage: Self.surfaces[tone.rawValue])
                .resizable(capInsets: EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 22), resizingMode: .stretch)
                .environment(\.layoutDirection, .leftToRight)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

// Original matte raster alternatives, scoped to Home and Library. Keep the older
// control atlas intact for screens outside this refinement.
struct MatteSurface: View {
    enum Tone: Int { case lime, pine, pineOnPaper, sageOnPaper }
    let tone: Tone
    private static let tiles: [UIImage] = {
        guard let source = UIImage(named: "ClipoMatteControls")?.cgImage else { return [] }
        // Measured silhouettes in the 1254px original. Extraction only, no drawing.
        let tops: [CGFloat] = [66, 379, 689, 996]
        let scale = CGFloat(source.width) / 1254
        return tops.compactMap { top in
            let bounds = CGRect(x: 65 * scale, y: top * scale,
                                width: 1125 * scale, height: 198 * scale)
            guard let tile = source.cropping(to: bounds.integral) else { return nil }
            return UIImage(cgImage: tile, scale: 3, orientation: .up)
        }
    }()
    var body: some View {
        if Self.tiles.indices.contains(tone.rawValue) {
            Image(uiImage: Self.tiles[tone.rawValue])
                .resizable(capInsets: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18), resizingMode: .stretch)
                .environment(\.layoutDirection, .leftToRight)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

struct MatteActionStyle: ButtonStyle {
    var onPaper = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.court(.footnote, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
            .foregroundStyle(onPaper ? ClipoStyle.ink : ClipoStyle.paper)
            .background { MatteSurface(tone: onPaper ? .sageOnPaper : .pine) }
            .contentShape(Rectangle())
            .opacity(!isEnabled ? 0.6 : (configuration.isPressed ? 0.75 : 1))
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
                        LocalizedText(value).font(.court(.footnote, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(minHeight: 44)
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

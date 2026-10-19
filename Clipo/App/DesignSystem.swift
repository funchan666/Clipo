import SwiftUI

// Native layout and typography; every pictorial mark comes from the original raster atlas.
enum ClipoStyle {
    static let background = Color(red: 0.055, green: 0.065, blue: 0.06)
    static let surface = Color(red: 0.105, green: 0.12, blue: 0.105)
    static let raised = Color(red: 0.16, green: 0.18, blue: 0.15)
    static let accent = Color(red: 0.847, green: 1, blue: 0.384)
    static let ink = Color(red: 0.055, green: 0.07, blue: 0.04)
    static let secondary = Color(red: 0.69, green: 0.73, blue: 0.67)
    static let danger = Color(red: 1, green: 0.64, blue: 0.59)
}
enum ClipoGlyph: Int {
    case home, feed, edit, library, link, search, bookmark, download
    case play, pause, close, back, sound, mute, folder, settings
}
struct Glyph: View {
    let symbol: ClipoGlyph
    var size: CGFloat = 25
    var body: some View {
        // Cell extraction is display-only: the source artwork is never redrawn in code.
        GeometryReader { geometry in
            Image("ClipoGlyphAtlas").resizable().interpolation(.high)
                .frame(width: geometry.size.width * 4, height: geometry.size.height * 4)
                .offset(x: -CGFloat(symbol.rawValue % 4) * geometry.size.width,
                        y: -CGFloat(symbol.rawValue / 4) * geometry.size.height)
        }
        .frame(width: size * 1.65, height: size * 1.65)
        .clipped().blendMode(.screen).accessibilityHidden(true)
    }
}
struct IconButton: View {
    let symbol: ClipoGlyph
    let label: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Glyph(symbol: symbol).frame(width: 48, height: 48)
                .background(selected ? ClipoStyle.raised : Color.clear, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(PressStyle()).accessibilityLabel(label)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
struct ActionButton: View {
    let title: String
    var primary = true
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(busy ? "Please wait…" : title).font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(primary ? ClipoStyle.ink : Color.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(primary ? ClipoStyle.accent : ClipoStyle.raised, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(PressStyle()).disabled(busy)
    }
}
struct PageHeading: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased()).font(.system(.caption, design: .monospaced).weight(.medium))
                .tracking(2).foregroundStyle(ClipoStyle.accent)
            Text(title).font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(.white)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct MessagePanel: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
            Text(message).font(.subheadline).foregroundStyle(ClipoStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action { ActionButton(title: actionTitle, primary: false, action: action) }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(ClipoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
struct ErrorNote: View {
    let message: String
    var body: some View {
        Text(message).font(.subheadline).foregroundStyle(ClipoStyle.danger)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            .accessibilityLabel("Error: \(message)")
    }
}
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.body).foregroundStyle(.white).padding(16)
            .background(ClipoStyle.raised, in: RoundedRectangle(cornerRadius: 14))
            .tint(ClipoStyle.accent)
    }
}
extension View { func clipoField() -> some View { modifier(FieldStyle()) } }
struct MediaCover: View {
    let url: URL?
    var folder = false
    var body: some View {
        ZStack {
            ClipoStyle.raised
            if folder { Glyph(symbol: .folder, size: 30) }
            else if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Glyph(symbol: .feed, size: 30) }
                }
            } else { Glyph(symbol: .feed, size: 30) }
        }.clipped()
    }
}
struct SheetHeading: View {
    let title: String
    var close: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.bold)).lineLimit(2)
            Spacer()
            IconButton(symbol: .close, label: "Close", action: close)
        }.padding(.horizontal, 20).padding(.top, 12)
    }
}

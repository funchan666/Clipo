import SwiftUI

// Bundled OFL fonts; no network requests or fixed Dynamic Type category.
extension Font {
    static func court(_ style: Font.TextStyle, weight: Font.Weight = .regular, editorial: Bool = false) -> Font {
        let points: CGFloat
        switch style {
        case .largeTitle: points = 34
        case .title: points = 28
        case .title2: points = 22
        case .title3: points = 20
        case .headline, .body: points = 17
        case .callout: points = 16
        case .subheadline: points = 15
        case .footnote: points = 13
        case .caption: points = 12
        case .caption2: points = 11
        @unknown default: points = 17
        }
        let semibold = weight == .semibold || weight == .bold || weight == .heavy || style == .headline
        let name = editorial ? "Lora-Regular" : (semibold ? "Barlow-SemiBold" : "Barlow-Regular")
        // Core Text supplies the system glyph cascade for Arabic, Japanese and Korean.
        return .custom(name, size: points, relativeTo: style)
    }
}

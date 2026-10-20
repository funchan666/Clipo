import SwiftUI

/// Independent of device language. Changing this preference never rebuilds the app's stores.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ko, ja, id, pt, ar, es
    static let preferenceKey = "clipo.language"
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "en") ?? .en
    }
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .en: "English"
        case .ko: "한국어"
        case .ja: "日本語"
        case .id: "Bahasa Indonesia"
        case .pt: "Português"
        case .ar: "العربية"
        case .es: "Español"
        }
    }
    var locale: Locale { Locale(identifier: rawValue) }
    var direction: LayoutDirection { self == .ar ? .rightToLeft : .leftToRight }
}

enum L10n {
    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues:
        AppLanguage.allCases.compactMap { language in
            guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return nil }
            return (language, bundle)
        })

    static func text(_ key: String, language: AppLanguage = .current) -> String {
        bundles[language]?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }

    /// Explicit arguments keep amounts, file names and server content out of translation lookup.
    static func format(_ key: String, _ arguments: [String], language: AppLanguage = .current) -> String {
        let template = text(key, language: language)
        let pattern = #"%(?:(\d+)\$)?@"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return template }
        let source = template as NSString
        var output = "", cursor = 0, nextArgument = 0
        for match in expression.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let position = match.range(at: 1)
            let index = position.location == NSNotFound ? nextArgument : (Int(source.substring(with: position)) ?? 1) - 1
            output += arguments.indices.contains(index) ? arguments[index] : source.substring(with: match.range)
            nextArgument += 1
            cursor = NSMaxRange(match.range)
        }
        output += source.substring(from: cursor)
        return output
    }
}

/// Localizes owned copy at display time, including String-valued labels from existing models.
/// Use Text(verbatim:) for remote titles, user file names and monetary amounts.
struct LocalizedText: View {
    let key: String
    var arguments: [String] = []
    @Environment(\.locale) private var locale
    init(_ key: String, _ arguments: String...) { self.key = key; self.arguments = arguments }
    var body: some View {
        let language = AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "en") ?? .en
        Text(verbatim: arguments.isEmpty ? L10n.text(key, language: language) : L10n.format(key, arguments, language: language))
    }
}

struct LanguagePicker: View {
    @AppStorage(AppLanguage.preferenceKey) private var languageCode = AppLanguage.en.rawValue
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "App language") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LocalizedText("Choose your language").font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 0) {
                        ForEach(AppLanguage.allCases) { language in
                            Button {
                                languageCode = language.rawValue
                            } label: {
                                HStack(spacing: 16) {
                                    Text(verbatim: language.nativeName).font(.body.weight(.medium))
                                        .environment(\.layoutDirection, language.direction)
                                    Spacer(minLength: 8)
                                    if languageCode == language.rawValue {
                                        LocalizedText("Selected").font(.caption.weight(.semibold))
                                            .foregroundStyle(ClipoStyle.accent)
                                    }
                                }.padding(20).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                    .background(languageCode == language.rawValue ? ClipoStyle.raised : Color.clear)
                                    .contentShape(Rectangle())
                            }.buttonStyle(PressStyle())
                                .accessibilityAddTraits(languageCode == language.rawValue ? .isSelected : [])
                                .accessibilityIdentifier("language.\(language.rawValue)")
                            if language != AppLanguage.allCases.last { Divider().overlay(ClipoStyle.line) }
                        }
                    }.background(ClipoStyle.surface).clipShape(RoundedRectangle(cornerRadius: 22))
                }.clipoPage()
            }
        }.foregroundStyle(ClipoStyle.paper).clipoScreenBackground()
    }
}

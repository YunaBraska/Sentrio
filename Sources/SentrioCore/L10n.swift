import Foundation

enum L10n {
    static let baseBundle: Bundle = .module

    /// When set, forces a specific localization bundle (e.g. "de", "pt-BR", "zh-Hans").
    /// When nil, the system language selection is used.
    static var overrideLocalization: String?

    static let supportedLocalizations: [String] = [
        "en",
        "es",
        "fr",
        "de",
        "it",
        "pt-BR",
        "nl",
        "sv",
        "da",
        "fi",
        "pl",
        "tr",
        "ru",
        "ja",
        "ko",
        "zh-Hans",
    ]

    static var bundle: Bundle {
        guard let overrideLocalization else { return baseBundle }
        return bundle(for: overrideLocalization) ?? baseBundle
    }

    static func bundle(for localization: String) -> Bundle? {
        guard let path = baseBundle.path(forResource: localization, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: args)
    }

    static func languageDisplayName(_ localization: String) -> String {
        switch localization {
        case "en": "English"
        case "es": "Español"
        case "fr": "Français"
        case "de": "Deutsch"
        case "it": "Italiano"
        case "pt-BR": "Português (Brasil)"
        case "nl": "Nederlands"
        case "sv": "Svenska"
        case "da": "Dansk"
        case "fi": "Suomi"
        case "pl": "Polski"
        case "tr": "Türkçe"
        case "ru": "Русский"
        case "ja": "日本語"
        case "ko": "한국어"
        case "zh-Hans": "简体中文"
        default: localization
        }
    }
}

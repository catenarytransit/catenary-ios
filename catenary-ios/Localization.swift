import Foundation
import SwiftUI

/// Centralized access for strings that are assembled outside SwiftUI's
/// localized-string-key initializers. Static SwiftUI literals continue to be
/// extracted into `Localizable.xcstrings` automatically.
enum L10n {
    static func string(
        _ key: String,
        defaultValue: String? = nil,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        localizedBundle(for: locale).localizedString(
            forKey: key,
            value: defaultValue ?? key,
            table: "Localizable"
        )
    }

    static func format(
        _ key: String,
        defaultValue: String,
        locale: Locale = .autoupdatingCurrent,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key, defaultValue: defaultValue, locale: locale),
            locale: locale,
            arguments: arguments
        )
    }

    static func key(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }

    private static func localizedBundle(for locale: Locale) -> Bundle {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        var candidates = [identifier]

        if identifier.lowercased().hasPrefix("zh-") {
            if identifier.localizedCaseInsensitiveContains("HK") {
                candidates.append("zh-HK")
            }
            if identifier.localizedCaseInsensitiveContains("Hant")
                || identifier.localizedCaseInsensitiveContains("TW") {
                candidates.append("zh-Hant")
            } else {
                candidates.append("zh-Hans")
            }
        }

        if let languageCode = locale.language.languageCode?.identifier {
            if languageCode == "no" || languageCode == "nb" {
                candidates.append("nb")
            }
            candidates.append(languageCode)
        }

        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
    }
}

import Foundation
import SwiftUI

/// Centralized access for strings that are assembled outside SwiftUI's
/// localized-string-key initializers. Prefer localized SwiftUI literals in
/// views and `String(localized:)`/`LocalizedStringResource` outside views.
enum L10n {
    static func string(
        _ key: String,
        defaultValue: String? = nil,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let resource = LocalizedStringResource(
            String.LocalizationValue(key),
            table: "Localizable",
            locale: locale,
            bundle: .main
        )
        let localized = String(localized: resource)

        // A dynamic key uses the key itself as LocalizedStringResource's
        // fallback. Preserve explicit English fallbacks for semantic keys.
        return localized == key ? (defaultValue ?? key) : localized
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
}

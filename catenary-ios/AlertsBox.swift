import Foundation
import SwiftUI
import UIKit

private let serviceAlertColor = Color(red: 249 / 255, green: 156 / 255, blue: 36 / 255)
let serviceAlertsBackground = Color(uiColor: .secondarySystemBackground)

struct AlertsBox: View {
    let alerts: [String: SingleTripAlert]
    let defaultTimezone: String?
    let chateauID: String?

    @Environment(\.locale) private var locale
    @State private var selectedLanguages = Set<String>()

    init(
        alerts: [String: SingleTripAlert],
        defaultTimezone: String? = nil,
        chateauID: String? = nil
    ) {
        self.alerts = alerts
        self.defaultTimezone = defaultTimezone
        self.chateauID = chateauID
    }

    @ViewBuilder
    var body: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                languagePicker

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(serviceAlertColor)
                            .accessibilityHidden(true)

                        Text(serviceAlertsTitle(alerts.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(serviceAlertColor)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)

                    alertItems
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(serviceAlertColor, lineWidth: 1)
                }
            }
            .task(id: languageSelectionKey) {
                selectedLanguages = [defaultAlertLanguage(languageList, locale: locale)]
            }
        }
    }

    private var languagePicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(languageList, id: \.self) { language in
                    let selected = effectiveSelectedLanguages.contains(language)
                    Button {
                        var updated = effectiveSelectedLanguages
                        if selected {
                            guard updated.count > 1 else { return }
                            updated.remove(language)
                        } else {
                            updated.insert(language)
                        }
                        selectedLanguages = updated
                    } label: {
                        Text(alertLanguageLabel(language))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(
                                selected ? Color.accentColor : Color.clear,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var alertItems: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(sortedAlerts.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                        .overlay(serviceAlertColor.opacity(0.5))
                        .padding(.vertical, 4)
                }

                AlertItemView(
                    alert: sortedAlerts[index].value,
                    languageList: languageList,
                    selectedLanguages: effectiveSelectedLanguages,
                    locale: locale,
                    defaultTimezone: defaultTimezone,
                    chateauID: chateauID
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var sortedAlerts: [(key: String, value: SingleTripAlert)] {
        alerts.sorted { $0.key < $1.key }
    }

    private var languageList: [String] {
        var languages: [String] = []

        for alert in sortedAlerts.map(\.value) {
            for language in alert.allTranslationLanguages {
                let normalizedLanguage = alertLanguageCode(language)
                if let existingIndex = languages.firstIndex(where: {
                    alertLanguageCode($0)
                        .localizedCaseInsensitiveCompare(normalizedLanguage) == .orderedSame
                }) {
                    let newIsHTML = language.lowercased().hasSuffix("-html")
                    let existingIsHTML = languages[existingIndex].lowercased().hasSuffix("-html")
                    if newIsHTML && !existingIsHTML {
                        languages[existingIndex] = language
                    }
                } else {
                    languages.append(language)
                }
            }
        }

        return languages.isEmpty ? [""] : languages
    }

    private var effectiveSelectedLanguages: Set<String> {
        let availableSelection = selectedLanguages.intersection(languageList)
        if !availableSelection.isEmpty {
            return availableSelection
        }
        return [defaultAlertLanguage(languageList, locale: locale)]
    }

    private var languageSelectionKey: String {
        languageList.joined(separator: "\u{1F}") + "|" + locale.identifier
    }
}

struct ServiceAlertsLink: View {
    let alerts: [SingleTripAlert]
    let action: () -> Void

    @Environment(\.locale) private var locale

    init(alerts: [String: SingleTripAlert], action: @escaping () -> Void) {
        self.alerts = alerts.sorted { $0.key < $1.key }.map(\.value)
        self.action = action
    }

    init(alerts: [SingleTripAlert], action: @escaping () -> Void) {
        self.alerts = alerts
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Text("!")
                    Text(String(alerts.count))
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(serviceAlertColor, in: Capsule())

                Text(localizedHeader)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                serviceAlertsBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open service alerts")
    }

    private var localizedHeader: String {
        guard let translation = alerts.first?.headerText?.preferredTranslation(locale: locale) else {
            return L10n.string("Service Alerts")
        }
        let plainText = AlertFormattedTextBuilder.plainText(
            from: translation.text,
            chateauID: nil
        )
        return plainText.isEmpty ? L10n.string("Service Alerts") : plainText
    }
}

struct ServiceAlertsScreen: View {
    let alerts: [String: SingleTripAlert]
    let defaultTimezone: String?
    let chateauID: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                serviceAlertsBackground.ignoresSafeArea()

                ScrollView {
                    AlertsBox(
                        alerts: alerts,
                        defaultTimezone: defaultTimezone,
                        chateauID: chateauID
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Service Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(serviceAlertsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .catenaryCircularButtonBorderShape()
                    .accessibilityLabel("Close service alerts")
                }
            }
        }
    }
}

private struct AlertItemView: View {
    let alert: SingleTripAlert
    let languageList: [String]
    let selectedLanguages: Set<String>
    let locale: Locale
    let defaultTimezone: String?
    let chateauID: String?

    private var visibleLanguages: [String] {
        languageList.filter {
            selectedLanguages.contains($0)
                && alert.hasDisplayableContent(for: $0, chateauID: chateauID)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(alertCauseDescription(alert.cause)) // \(alertEffectDescription(alert.effect))")
                .font(.body.weight(.medium))
                .foregroundStyle(serviceAlertColor)

            ForEach(visibleLanguages.indices, id: \.self) { index in
                let language = visibleLanguages[index]
                if index > 0 {
                    Divider()
                        .overlay(serviceAlertColor.opacity(0.35))
                        .padding(.vertical, 4)
                }

                if let urlTranslation = alert.url?.nonEmptyTranslation(for: language) {
                    AlertURLView(translation: urlTranslation)
                }

                let textTranslations = alert.displayTextTranslations(
                    for: language,
                    chateauID: chateauID
                )
                ForEach(textTranslations.indices, id: \.self) { textIndex in
                    AlertFormattedText(
                        text: textTranslations[textIndex].text,
                        chateauID: chateauID
                    )
                }
            }

            AlertActivePeriodsView(
                activePeriods: alert.activePeriod,
                locale: locale,
                defaultTimezone: defaultTimezone
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}

private struct AlertURLView: View {
    let translation: SingleTripAlertTranslation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            let language = translation.language ?? L10n.string("Link")
            Text(verbatim: "\(language): ")
                .font(.caption)

            if let url = URL(string: translation.text) {
                Link(translation.text, destination: url)
                    .font(.caption)
                    .foregroundStyle(.blue)
            } else {
                Text(translation.text)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct AlertActivePeriodsView: View {
    let activePeriods: [SingleTripAlertActivePeriod]
    let locale: Locale
    let defaultTimezone: String?

    var body: some View {
        if !activePeriods.isEmpty {
            let scheduleLocale = alertScheduleLocale(locale)
            let schedule = condenseActivePeriods(
                periods: activePeriods,
                locale: scheduleLocale,
                defaultTimezone: defaultTimezone
            )

            if schedule.isCondensed {
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.baseRule)
                        .font(.caption.weight(.bold))

                    if !schedule.weekdayRules.isEmpty {
                        Text(schedule.weekdayRules)
                            .font(.caption.weight(.bold))
                    }

                    if !schedule.exceptions.isEmpty {
                        alertExceptionText(schedule.exceptions)
                            .font(.caption)
                    }
                }
                .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(schedule.fallbackPeriods.indices, id: \.self) { index in
                        AlertActivePeriodRow(
                            activePeriod: schedule.fallbackPeriods[index],
                            locale: locale,
                            defaultTimezone: defaultTimezone
                        )
                    }
                }
            }
        }
    }

    private func alertExceptionText(_ text: String) -> Text {
        guard let separator = text.range(of: ": ") else { return Text(text) }
        let label = String(text[..<separator.lowerBound]) + ":"
        return Text("\(Text(label).bold()) \(String(text[separator.upperBound...]))")

    }
}

private struct AlertActivePeriodRow: View {
    let activePeriod: SingleTripAlertActivePeriod
    let locale: Locale
    let defaultTimezone: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let start = activePeriod.start {
                periodRow(label: "Starting time", epochSeconds: start)
            }
            if let end = activePeriod.end {
                periodRow(label: "Ending time", epochSeconds: end)
            }
        }
    }

    private func periodRow(label: LocalizedStringKey, epochSeconds: Int64) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            
            Text("\(Text(label))\(Text(verbatim: ": \(formattedDate(epochSeconds))"))")
                .font(.caption)

            SelfUpdatingDiffTimer(
                targetTimeSeconds: epochSeconds,
                showBrackets: true,
                showSeconds: true,
                showDays: true,
                numSize: 12,
                unitSize: 10,
                bracketSize: 12,
                locale: locale
            )
        }
    }

    private func formattedDate(_ epochSeconds: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = defaultTimezone.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }
}

private struct AlertFormattedText: View {
    let text: String
    let chateauID: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(AlertFormattedTextBuilder.make(from: text, chateauID: chateauID))
            .font(.footnote)
            .foregroundStyle(.primary)
            .tint(colorScheme == .dark ? Color(red: 43 / 255, green: 127 / 255, blue: 1) : .blue)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

private enum AlertFormattedTextBuilder {
    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"<(/?[a-zA-Z0-9]+)(\s[^>]*)?>|([^<]+)"#
    )
    private static let hrefRegex = try! NSRegularExpression(
        pattern: #"href\s*=\s*[\"']([^\"']+)[\"']"#
    )

    static func make(from source: String, chateauID: String?) -> AttributedString {
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        var output = AttributedString()
        var boldDepth = 0
        var activeLink: URL?
        var justAddedBullet = false

        func appendFragment(_ source: String) {
            let rendered = renderedText(source, chateauID: chateauID)
            guard !rendered.isEmpty else { return }

            var fragment = AttributedString(rendered)
            if boldDepth > 0 {
                fragment.font = .footnote.bold()
            }
            if let activeLink {
                fragment.link = activeLink
            }
            output.append(fragment)
        }

        func ensureNewlines(_ count: Int) {
            guard !output.characters.isEmpty else { return }
            let existing = String(output.characters).reversed().prefix { $0 == "\n" }.count
            guard existing < count else { return }
            output.append(AttributedString(String(repeating: "\n", count: count - existing)))
        }

        for match in tokenRegex.matches(in: source, range: fullRange) {
            if let content = capture(3, in: match, source: source), !content.isEmpty {
                justAddedBullet = false
                appendFragment(content)
                continue
            }

            guard let rawTag = capture(1, in: match, source: source) else { continue }
            let tag = rawTag.lowercased()
            let attributes = capture(2, in: match, source: source) ?? ""
            if attributes.contains("min-height") { continue }

            switch tag {
            case "a":
                if let href = firstMatch(in: attributes, regex: hrefRegex, capture: 1) {
                    let decodedHref = decodeEntities(href)
                    if let url = URL(string: decodedHref),
                       ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                        activeLink = url
                    }
                }
            case "/a":
                activeLink = nil
            case "b", "strong":
                boldDepth += 1
            case "/b", "/strong":
                boldDepth = max(0, boldDepth - 1)
            case "br":
                ensureNewlines(1)
                justAddedBullet = false
            case "p":
                if !justAddedBullet { ensureNewlines(2) }
                justAddedBullet = false
            case "/p":
                ensureNewlines(1)
                justAddedBullet = false
            case "ul", "/ul":
                ensureNewlines(1)
                justAddedBullet = false
            case "li":
                ensureNewlines(1)
                appendFragment("  • ")
                justAddedBullet = true
            default:
                break
            }
        }

        let renderedOutput = String(output.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard renderedOutput.isEmpty else { return output }

        let fallback = renderedText(
            source.replacingOccurrences(
                of: #"<[^>]+>"#,
                with: " ",
                options: .regularExpression
            ),
            chateauID: chateauID
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return fallback.isEmpty ? output : AttributedString(fallback)
    }

    static func plainText(from source: String, chateauID: String?) -> String {
        String(make(from: source, chateauID: chateauID).characters)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func renderedText(_ source: String, chateauID: String?) -> String {
        let decoded = decodeEntities(source)
        guard chateauID == "nyct" else { return decoded }

        return decoded
            .replacingOccurrences(of: "[shuttle bus icon]", with: "[S]")
            .replacingOccurrences(of: "[accessibility icon]", with: "♿︎")
    }

    private static func decodeEntities(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func capture(_ index: Int, in match: NSTextCheckingResult, source: String) -> String? {
        guard match.numberOfRanges > index,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else { return nil }
        return String(source[range])
    }

    private static func firstMatch(
        in source: String,
        regex: NSRegularExpression,
        capture index: Int
    ) -> String? {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range) else { return nil }
        return capture(index, in: match, source: source)
    }
}

private func alertLanguageCode(_ language: String) -> String {
    let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
    let withoutHTML = trimmed.lowercased().hasSuffix("-html")
        ? String(trimmed.dropLast("-html".count))
        : trimmed
    let normalized = withoutHTML.replacingOccurrences(of: "_", with: "-")
    return normalized.localizedCaseInsensitiveCompare("und") == .orderedSame ? "" : normalized
}

private func defaultAlertLanguage(_ languages: [String], locale: Locale) -> String {
    guard let first = languages.first else { return "" }
    let localeTag = locale.identifier.replacingOccurrences(of: "_", with: "-")
    let localeLanguage = locale.language.languageCode?.identifier
        ?? localeTag.split(separator: "-").first.map(String.init)
        ?? ""

    return languages.first {
        alertLanguageCode($0).localizedCaseInsensitiveCompare(localeTag) == .orderedSame
    } ?? languages.first {
        alertLanguageCode($0).split(separator: "-").first.map(String.init)?
            .localizedCaseInsensitiveCompare(localeLanguage) == .orderedSame
    } ?? first
}

private func alertLanguageLabel(_ language: String) -> String {
    let label = alertLanguageCode(language)
    return label.isEmpty ? "und" : label
}

private func alertScheduleLocale(_ locale: Locale) -> Locale {
    locale.language.languageCode?.identifier.lowercased() == "en"
        ? Locale(identifier: "en_CA")
        : locale
}

private func serviceAlertsTitle(_ count: Int) -> String {
    L10n.format("alerts.count", defaultValue: "Service alerts: %d", count)
}

private func alertCauseDescription(_ cause: Int?) -> String {
    let key: String
    switch cause {
    case 1: key = "Unknown cause"
    case 2: key = "Other cause"
    case 3: key = "Technical problem"
    case 4: key = "Labour strike"
    case 5: key = "Demonstration or street blockage"
    case 6: key = "Accident"
    case 7: key = "Holiday"
    case 8: key = "Weather"
    case 9: key = "Maintenance"
    case 10: key = "Construction"
    case 11: key = "Police activity"
    case 12: key = "Medical emergency"
    default: key = "Unknown cause"
    }
    return L10n.string(key)
}

private func alertEffectDescription(_ effect: Int?) -> String {
    let key: String
    switch effect {
    case 1: key = "No service"
    case 2: key = "Reduced service"
    case 3: key = "Significant delays"
    case 4: key = "Detour"
    case 5: key = "Additional service"
    case 6: key = "Modified service"
    case 7: key = "Other effect"
    case 8: key = "Unknown effect"
    case 9: key = "Stop moved"
    case 10: key = "No effect"
    case 11: key = "Accessibility issue"
    default: key = "Unknown effect"
    }
    return L10n.string(key)
}

private extension SingleTripAlertText {
    func translation(for language: String) -> SingleTripAlertTranslation? {
        let normalizedLanguage = alertLanguageCode(language)
        let exactMatches = translation.filter { ($0.language ?? "") == language }
        let normalizedMatches = translation.filter {
            alertLanguageCode($0.language ?? "")
                .localizedCaseInsensitiveCompare(normalizedLanguage) == .orderedSame
        }

        return exactMatches.first(where: {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) ?? normalizedMatches.first(where: {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) ?? exactMatches.first ?? normalizedMatches.first
    }

    func nonEmptyTranslation(for language: String) -> SingleTripAlertTranslation? {
        guard let translation = translation(for: language),
              !translation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return translation
    }

    func displayableTranslation(
        for language: String,
        chateauID: String?
    ) -> SingleTripAlertTranslation? {
        guard let translation = nonEmptyTranslation(for: language),
              !AlertFormattedTextBuilder.plainText(
                from: translation.text,
                chateauID: chateauID
              ).isEmpty else {
            return nil
        }
        return translation
    }
}

private extension SingleTripAlert {
    var textualFields: [SingleTripAlertText] {
        [
            headerText,
            descriptionText,
            ttsHeaderText,
            ttsDescriptionText,
            causeDetail,
            effectDetail
        ].compactMap { $0 }
    }

    var allTranslationLanguages: [String] {
        var fields = textualFields
        if let url {
            fields.append(url)
        }

        return fields.flatMap { field in
            field.translation.map { $0.language ?? "" }
        }
    }

    func displayTextTranslations(
        for language: String,
        chateauID: String?
    ) -> [SingleTripAlertTranslation] {
        let candidates: [SingleTripAlertTranslation] = [
            headerText?.displayableTranslation(for: language, chateauID: chateauID)
                ?? ttsHeaderText?.displayableTranslation(for: language, chateauID: chateauID),
            descriptionText?.displayableTranslation(for: language, chateauID: chateauID)
                ?? ttsDescriptionText?.displayableTranslation(for: language, chateauID: chateauID),
            causeDetail?.displayableTranslation(for: language, chateauID: chateauID),
            effectDetail?.displayableTranslation(for: language, chateauID: chateauID)
        ].compactMap { $0 }

        var seenText = Set<String>()
        return candidates.filter { translation in
            let key = AlertFormattedTextBuilder.plainText(
                from: translation.text,
                chateauID: chateauID
            ).lowercased()
            return !key.isEmpty && seenText.insert(key).inserted
        }
    }

    func hasDisplayableContent(for language: String, chateauID: String?) -> Bool {
        !displayTextTranslations(for: language, chateauID: chateauID).isEmpty
            || url?.nonEmptyTranslation(for: language) != nil
    }
}


import Foundation
import SwiftUI
import UIKit
import WebKit

private let serviceAlertColor = Color(red: 249 / 255, green: 156 / 255, blue: 36 / 255)

struct AlertsBox: View {
    let alerts: [String: SingleTripAlert]
    let defaultTimezone: String?
    let chateauID: String?
    let isScrollable: Bool

    @Environment(\.locale) private var locale
    @State private var expanded: Bool
    @State private var selectedLanguages = Set<String>()

    init(
        alerts: [String: SingleTripAlert],
        defaultTimezone: String? = nil,
        chateauID: String? = nil,
        isScrollable: Bool = false,
        initiallyExpanded: Bool = true
    ) {
        self.alerts = alerts
        self.defaultTimezone = defaultTimezone
        self.chateauID = chateauID
        self.isScrollable = isScrollable
        _expanded = State(initialValue: initiallyExpanded)
    }

    @ViewBuilder
    var body: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if expanded {
                    languagePicker
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(serviceAlertColor)
                                .accessibilityHidden(true)

                            Text(serviceAlertsTitle(alerts.count))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(serviceAlertColor)

                            Spacer(minLength: 8)

                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .accessibilityLabel(expanded ? "Collapse service alerts" : "Expand service alerts")

                    if expanded {
                        expandedAlertContent
                            .transition(.opacity)
                    }
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
                    let selected = selectedLanguages.contains(language)
                    Button {
                        if selected {
                            guard selectedLanguages.count > 1 else { return }
                            selectedLanguages.remove(language)
                        } else {
                            selectedLanguages.insert(language)
                        }
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

    @ViewBuilder
    private var expandedAlertContent: some View {
        if isScrollable {
            GeometryReader { proxy in
                ScrollView {
                    alertItems
                }
                .frame(maxHeight: proxy.size.height * 0.8)
            }
            .frame(maxHeight: .infinity)
        } else {
            alertItems
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
                    selectedLanguages: selectedLanguages,
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
            for language in alert.allTranslationLanguages where !languages.contains(language) {
                languages.append(language)
            }
        }

        guard !languages.isEmpty else { return [""] }
        let htmlLanguages = languages.filter { $0.hasSuffix("-html") }
        let baseLanguagesToHide = Set(htmlLanguages.map { String($0.dropLast("-html".count)) })
        return languages.filter { !baseLanguagesToHide.contains($0) }
    }

    private var languageSelectionKey: String {
        languageList.joined(separator: "\u{1F}") + "|" + locale.identifier
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
            selectedLanguages.contains($0) && alert.hasTranslation(for: $0)
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

                if let urlTranslation = alert.url?.translation(for: language) {
                    AlertURLView(translation: urlTranslation)
                }

                if let header = alert.headerText?.translation(for: language) {
                    AlertFormattedText(text: header.text, chateauID: chateauID)
                }

                if let description = alert.descriptionText?.translation(for: language) {
                    AlertFormattedText(text: description.text, chateauID: chateauID)
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
            Text("\(translation.language ?? "Link"): ")
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

    private func periodRow(label: String, epochSeconds: Int64) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(label): \(formattedDate(epochSeconds))")
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
    @State private var measuredHeight: CGFloat = 1

    var body: some View {
        AlertHTMLView(
            html: AlertHTMLDocument.make(
                from: text,
                chateauID: chateauID,
                colorScheme: colorScheme
            ),
            measuredHeight: $measuredHeight
        )
        .frame(height: max(measuredHeight, 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AlertHTMLView: UIViewRepresentable {
    let html: String
    @Binding var measuredHeight: CGFloat

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AlertHTMLView
        var contentSizeObservation: NSKeyValueObservation?
        var lastHTML: String?

        init(parent: AlertHTMLView) {
            self.parent = parent
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInset = .zero
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.contentSizeObservation = webView.scrollView.observe(
            \.contentSize,
            options: [.initial, .new]
        ) { _, change in
            let height = max(change.newValue?.height ?? 1, 1)
            DispatchQueue.main.async {
                context.coordinator.parent.measuredHeight = height
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.contentSizeObservation?.invalidate()
        webView.navigationDelegate = nil
    }
}

private enum AlertHTMLDocument {
    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"<(/?[a-zA-Z0-9]+)(\s[^>]*)?>|([^<]+)"#
    )
    private static let hrefRegex = try! NSRegularExpression(pattern: #"href\s*=\s*[\"']([^\"']+)[\"']"#)
    private static let mtaIconRegex = try! NSRegularExpression(
        pattern: #"\[([A-Z0-9]+|shuttle bus icon|accessibility icon)\]"#
    )

    static func make(from source: String, chateauID: String?, colorScheme: ColorScheme) -> String {
        let body = supportedHTML(from: source, chateauID: chateauID)
        let textColor = colorScheme == .dark ? "#FFFFFF" : "#000000"
        let linkColor = colorScheme == .dark ? "#2B7FFF" : "#0000EE"
        let fontSize = UIFont.preferredFont(forTextStyle: .footnote).pointSize

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
          <style>
            html, body { margin: 0; padding: 0; background: transparent; }
            body {
              color: \(textColor);
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              font-size: \(fontSize)px;
              line-height: 1.25;
              overflow-wrap: anywhere;
            }
            a { color: \(linkColor); text-decoration: underline; }
            p { margin: 0 0 0.65em 0; }
            ul { margin: 0.15em 0 0.65em 1.25em; padding: 0; }
            li { margin: 0; padding: 0; }
            .mta-icon { width: 16px; height: 16px; vertical-align: -3px; object-fit: contain; }
          </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private static func supportedHTML(from source: String, chateauID: String?) -> String {
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        var output = ""

        for match in tokenRegex.matches(in: source, range: fullRange) {
            if let content = capture(3, in: match, source: source), !content.isEmpty {
                output += renderedText(content, chateauID: chateauID)
                continue
            }

            guard let rawTag = capture(1, in: match, source: source) else { continue }
            let tag = rawTag.lowercased()
            let attributes = capture(2, in: match, source: source) ?? ""
            if attributes.contains("min-height") { continue }

            switch tag {
            case "a":
                if let href = firstMatch(in: attributes, regex: hrefRegex, capture: 1),
                   let url = URL(string: href),
                   ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                    output += "<a href=\"\(escapeAttribute(href))\">"
                }
            case "/a": output += "</a>"
            case "b", "strong": output += "<strong>"
            case "/b", "/strong": output += "</strong>"
            case "br": output += "<br>"
            case "p": output += "<p>"
            case "/p": output += "</p>"
            case "ul": output += "<ul>"
            case "/ul": output += "</ul>"
            case "li": output += "<li>"
            case "/li": output += "</li>"
            default: break
            }
        }
        return output
    }

    private static func renderedText(_ source: String, chateauID: String?) -> String {
        guard chateauID == "nyct" else {
            return escapeText(source).replacingOccurrences(of: "\n", with: "<br>")
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var output = ""
        var cursor = source.startIndex

        for match in mtaIconRegex.matches(in: source, range: range) {
            guard let matchRange = Range(match.range, in: source),
                  let rawID = capture(1, in: match, source: source) else { continue }
            output += escapeText(String(source[cursor..<matchRange.lowerBound]))

            let routeID: String
            switch rawID {
            case "shuttle bus icon": routeID = "GS"
            case "accessibility icon": routeID = "ADA"
            default: routeID = rawID
            }

            if let iconURL = MTAAlertIcon.url(for: routeID) {
                output += "<img class=\"mta-icon\" src=\"\(escapeAttribute(iconURL.absoluteString))\" alt=\"\(escapeAttribute(rawID))\">"
            } else {
                output += escapeText(String(source[matchRange]))
            }
            cursor = matchRange.upperBound
        }

        output += escapeText(String(source[cursor...]))
        return output.replacingOccurrences(of: "\n", with: "<br>")
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

    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private enum MTAAlertIcon {
    private static let routeIDs: Set<String> = [
        "A", "C", "E", "B", "D", "F", "FX", "M", "G", "J", "Z",
        "L", "N", "Q", "R", "W", "GS", "FS", "H", "SIR", "1", "2", "3",
        "4", "5", "6", "6X", "7", "7X"
    ]

    static func url(for rawRouteID: String) -> URL? {
        let routeID = rawRouteID.uppercased()
        if routeID == "ADA" {
            return URL(string: "https://maps.catenarymaps.org/mtaicons/ada.svg")
        }
        guard routeIDs.contains(routeID) else { return nil }

        let iconName: String
        switch routeID {
        case "6X": iconName = "6d"
        case "7X": iconName = "7d"
        case "FX": iconName = "fd"
        case "GS", "FS", "H": iconName = "s"
        case "SIR": iconName = "sir"
        default: iconName = routeID.lowercased()
        }
        return URL(string: "https://maps.catenarymaps.org/mtaicons/\(iconName).svg")
    }
}

private func alertLanguageCode(_ language: String) -> String {
    let withoutHTML = language.hasSuffix("-html")
        ? String(language.dropLast("-html".count))
        : language
    return withoutHTML.replacingOccurrences(of: "_", with: "-")
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
    count == 1 ? "Service Alert (1)" : "Service Alerts (\(count))"
}

private func alertCauseDescription(_ cause: Int?) -> String {
    switch cause {
    case 1: "Unknown cause"
    case 2: "Other cause"
    case 3: "Technical problem"
    case 4: "Labour strike"
    case 5: "Demonstration or street blockage"
    case 6: "Accident"
    case 7: "Holiday"
    case 8: "Weather"
    case 9: "Maintenance"
    case 10: "Construction"
    case 11: "Police activity"
    case 12: "Medical emergency"
    default: "Unknown cause"
    }
}

private func alertEffectDescription(_ effect: Int?) -> String {
    switch effect {
    case 1: "No service"
    case 2: "Reduced service"
    case 3: "Significant delays"
    case 4: "Detour"
    case 5: "Additional service"
    case 6: "Modified service"
    case 7: "Other effect"
    case 8: "Unknown effect"
    case 9: "Stop moved"
    case 10: "No effect"
    case 11: "Accessibility issue"
    default: "Unknown effect"
    }
}

private extension SingleTripAlertText {
    func translation(for language: String) -> SingleTripAlertTranslation? {
        translation.first { ($0.language ?? "") == language }
            ?? translation.first {
                alertLanguageCode($0.language ?? "")
                    .localizedCaseInsensitiveCompare(alertLanguageCode(language)) == .orderedSame
            }
    }
}

private extension SingleTripAlert {
    var allTranslationLanguages: [String] {
        var languages: [String] = []

        if let headerText = headerText {
            languages.append(contentsOf: headerText.translation.map { translation in
                translation.language ?? ""
            })
        }

        if let descriptionText = descriptionText {
            languages.append(contentsOf: descriptionText.translation.map { translation in
                translation.language ?? ""
            })
        }

        if let url = url {
            languages.append(contentsOf: url.translation.map { translation in
                translation.language ?? ""
            })
        }

        return languages
    }

    func hasTranslation(for language: String) -> Bool {
        headerText?.translation(for: language) != nil
            || descriptionText?.translation(for: language) != nil
            || url?.translation(for: language) != nil
    }
}


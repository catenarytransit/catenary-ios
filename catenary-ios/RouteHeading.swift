//
//  RouteHeading.swift
//  catenary-ios
//

import Foundation
import SwiftUI
import UIKit
import WebKit

struct RouteHeading<Controls: View>: View {
    let color: String
    let textColor: String
    let routeType: Int?
    let agencyName: String?
    let shortName: String?
    let longName: String?
    let description: String?
    let tripShortName: String?
    let chateauID: String?
    let isCompact: Bool
    let routeClickable: Bool
    let headsign: String?
    let onRouteClick: (() -> Void)?

    private let controls: Controls

    @Environment(\.colorScheme) private var colorScheme

    init(
        color: String,
        textColor: String,
        routeType: Int?,
        agencyName: String?,
        shortName: String?,
        longName: String?,
        description: String? = nil,
        tripShortName: String? = nil,
        chateauID: String? = nil,
        isCompact: Bool,
        routeClickable: Bool = false,
        headsign: String? = nil,
        onRouteClick: (() -> Void)? = nil,
        @ViewBuilder controls: () -> Controls
    ) {
        self.color = color
        self.textColor = textColor
        self.routeType = routeType
        self.agencyName = agencyName
        self.shortName = shortName
        self.longName = longName
        self.description = description
        self.tripShortName = tripShortName
        self.chateauID = chateauID
        self.isCompact = isCompact
        self.routeClickable = routeClickable
        self.headsign = headsign
        self.onRouteClick = onRouteClick
        self.controls = controls()
    }

    @ViewBuilder
    var body: some View {
        if !isCompact {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 0) {
                        routeHeader

                        if let headsign {
                            Text(headsign)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let agencyName = nonBlank(agencyName) {
                            Text(agencyName)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if isDBFernverkehr, let shortName = nonBlank(shortName) {
                            Text(verbatim: L10n.format(
                                "route.line",
                                defaultValue: "Linie %@",
                                shortName
                            ))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let description = nonBlank(description) {
                            Text(description)
                                .font(.body)
                                .padding(.top, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.trailing, 48)

                    controls
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var routeHeader: some View {
        if routeClickable, let onRouteClick {
            Button(action: onRouteClick) {
                routeHeaderLabel
            }
            .buttonStyle(.plain)
        } else {
            routeHeaderLabel
        }
    }

    private var routeHeaderLabel: some View {
        HStack(alignment: .center, spacing: 8) {
            if let iconKind {
                routeIcon(iconKind)
            }

            routeTitleText
                .font(.headline)
                .foregroundStyle(displayColor.swiftUIColor)
                .underline(routeClickable)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func routeIcon(_ kind: RouteIconKind) -> some View {
        switch kind {
        case let .ratp(url):
            RemoteSVGImage(
                url: url,
                accessibilityLabel: shortName ?? L10n.string("Route")
            ) {
                genericBadge(
                    text: cleanedShortName,
                    background: routeColor,
                    foreground: routeTextColor,
                    isSBahn: false
                )
            }
            .frame(width: 44, height: 32)

        case let .mta(url, background, symbol):
            RemoteSVGImage(
                url: url,
                accessibilityLabel: shortName ?? L10n.string("Route")
            ) {
                mtaFallbackBadge(background: background, symbol: symbol)
            }
            .frame(width: 32, height: 32)

        case .sbb:
            HStack(spacing: 0) {
                SBBRouteLogo(
                    text: shortName ?? "",
                    foreground: routeTextColor
                )
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(routeColor.swiftUIColor)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

        case let .generic(isSBahn):
            genericBadge(
                text: cleanedShortName,
                background: routeColor,
                foreground: routeTextColor,
                isSBahn: isSBahn
            )
        }
    }

    @ViewBuilder
    private func genericBadge(
        text: String,
        background: RouteHeadingColor,
        foreground: RouteHeadingColor,
        isSBahn: Bool
    ) -> some View {
        let label = Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(foreground.swiftUIColor)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background.swiftUIColor)

        if isSBahn {
            label.clipShape(Capsule())
        } else {
            label.clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    private func mtaFallbackBadge(
        background: RouteHeadingColor,
        symbol: String
    ) -> some View {
        ZStack {
            Circle()
                .fill(background.swiftUIColor)
            Text(symbol)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .frame(width: 24, height: 24)
    }

    private var routeColor: RouteHeadingColor {
        RouteHeadingColor(hex: color) ?? .iosAccent
    }

    private var routeTextColor: RouteHeadingColor {
        RouteHeadingColor(hex: textColor) ?? .white
    }

    private var displayColor: RouteHeadingColor {
        switch colorScheme {
        case .dark:
            return routeColor.lightenedToContrastAgainstBlack(minimumRatio: 7.0)
        default:
            return routeColor.darkenedToContrastAgainstWhite(minimumRatio: 4.5)
        }
    }

    private var iconKind: RouteIconKind? {
        if isRATP, let url = RATPRouteStyle.iconURL(for: shortName) {
            return .ratp(url)
        }

        if isMTA, let shortName {
            let color = MTASubwayStyle.color(for: shortName)
            let symbol = MTASubwayStyle.symbolShortName(for: shortName)
            return .mta(
                url: MTASubwayStyle.iconURL(for: shortName),
                background: color,
                symbol: symbol
            )
        }

        if isSBB {
            return .sbb
        }

        if !isDBFernverkehr,
           nonBlank(shortName) != nil,
           (!isNationalRail || isLondonOverground || isElizabethLine),
           chateauID != "metrolinktrains" {
            return .generic(isSBahn: isSBahn)
        }

        return nil
    }

    private var routeTitleText: Text {
        var result = Text("")
        var hasText = false

        if iconKind == nil,
           (nonBlank(shortName) != nil || isDBFernverkehr),
           (!isNationalRail || isLondonOverground || isElizabethLine) {
            let value = isDBFernverkehr ? (dbDisplayName ?? "") : cleanedShortName
            result = Text("\(result)\(Text(value).bold())")
            hasText = true
            
        }

        if let longName = nonBlank(longName),
           chateauID != "metrolinktrains",
           shouldShowLongName(longName) {
            if hasText {
                result = Text("\(result) ")
            }
            result = Text("\(result)\(Text(longName))")
            hasText = true
        }

        if let tripShortName = nonBlank(tripShortName), !isDBFernverkehr {
            if hasText {
                result = Text("\(result) ")
            }
            result = Text("\(result)\(Text(tripShortName).bold())")
        }

        return result
    }

    private func shouldShowLongName(_ value: String) -> Bool {
        if chateauID == "viarail" {
            return true
        }
        if !isNationalRail {
            return true
        }

        let containsTo = value.range(of: " to ", options: [.caseInsensitive]) != nil
        return !containsTo || isLondonOverground || isElizabethLine
    }

    private var cleanedShortName: String {
        (shortName ?? "").replacingOccurrences(of: " Line", with: "")
    }

    private var isRATP: Bool {
        RATPRouteStyle.isIDFMChateau(chateauID) && RATPRouteStyle.hasIcon(for: shortName)
    }

    private var isMTA: Bool {
        chateauID == MTASubwayStyle.chateauID
            && !(shortName?.isEmpty ?? true)
            && MTASubwayStyle.isSubwayRouteID(shortName ?? "")
    }

    private var isSBB: Bool {
        guard chateauID == "schweiz", let shortName, !shortName.isEmpty else {
            return false
        }
        return shortName.hasPrefix("IR") || shortName.hasPrefix("IC") || shortName == "EC"
    }

    private var isNationalRail: Bool {
        chateauID == "nationalrailuk"
    }

    private var isLondonOverground: Bool {
        shortName?.hasPrefix("LO-") == true
    }

    private var isElizabethLine: Bool {
        shortName == "XR-ELIZABETH"
    }

    private var isDBFernverkehr: Bool {
        chateauID == "deutschland"
            && (agencyName == "DB Fernverkehr AG"
                || agencyName == "DB Fernverkehr (Codesharing)")
    }

    private var isSBahn: Bool {
        guard chateauID == "vbb" || chateauID == "deutschland",
              let shortName else {
            return false
        }
        return shortName.range(of: #"^S\d+"#, options: .regularExpression) != nil
    }

    private var dbDisplayName: String? {
        guard isDBFernverkehr else {
            return nil
        }
        guard let tripShortName else {
            return nil
        }

        let withoutLeadingZeroes = tripShortName.replacingOccurrences(
            of: #"^0+"#,
            with: "",
            options: .regularExpression
        )
        return DBFernverkehrLookup.displayName(for: withoutLeadingZeroes) ?? tripShortName
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

extension RouteHeading where Controls == EmptyView {
    init(
        color: String,
        textColor: String,
        routeType: Int?,
        agencyName: String?,
        shortName: String?,
        longName: String?,
        description: String? = nil,
        tripShortName: String? = nil,
        chateauID: String? = nil,
        isCompact: Bool,
        routeClickable: Bool = false,
        headsign: String? = nil,
        onRouteClick: (() -> Void)? = nil
    ) {
        self.init(
            color: color,
            textColor: textColor,
            routeType: routeType,
            agencyName: agencyName,
            shortName: shortName,
            longName: longName,
            description: description,
            tripShortName: tripShortName,
            chateauID: chateauID,
            isCompact: isCompact,
            routeClickable: routeClickable,
            headsign: headsign,
            onRouteClick: onRouteClick
        ) {
            EmptyView()
        }
    }
}

private enum RouteIconKind: Equatable {
    case ratp(URL)
    case mta(url: URL?, background: RouteHeadingColor, symbol: String)
    case sbb
    case generic(isSBahn: Bool)
}

private enum RATPRouteStyle {
    static let idfmChateauID = "île~de~france~mobilités"

    private static let iconNames: [String: String] = [
        // Métro
        "1": "metro_1", "2": "metro_2", "3": "metro_3",
        "3b": "metro_3bis", "3bis": "metro_3bis", "4": "metro_4",
        "5": "metro_5", "6": "metro_6", "7": "metro_7",
        "7b": "metro_7bis", "7bis": "metro_7bis", "8": "metro_8",
        "9": "metro_9", "10": "metro_10", "11": "metro_11",
        "12": "metro_12", "13": "metro_13", "14": "metro_14",
        "15": "metro_15", "16": "metro_16", "17": "metro_17",
        "18": "metro_18", "19": "metro_19",

        // RER
        "a": "rer_a", "b": "rer_b", "c": "rer_c",
        "d": "rer_d", "e": "rer_e",

        // Transilien
        "h": "train_h", "j": "train_j", "k": "train_k",
        "l": "train_l", "n": "train_n", "p": "train_p",
        "r": "train_r", "u": "train_u", "v": "train_v",

        // Tram
        "t1": "tram_1", "t2": "tram_2", "t3a": "tram_3a",
        "t3b": "tram_3b", "t4": "tram_4", "t5": "tram_5",
        "t6": "tram_6", "t7": "tram_7", "t8": "tram_8",
        "t9": "tram_9", "t10": "tram_10", "t11": "tram_11",
        "t12": "tram_12", "t13": "tram_13", "t14": "tram_14"
    ]

    static func isIDFMChateau(_ chateauID: String?) -> Bool {
        chateauID == idfmChateauID
    }

    static func hasIcon(for shortName: String?) -> Bool {
        normalized(shortName).flatMap { iconNames[$0] } != nil
    }

    static func iconURL(for shortName: String?) -> URL? {
        guard let key = normalized(shortName), let iconName = iconNames[key] else {
            return nil
        }
        return URL(string: "https://maps.catenarymaps.org/ratp/\(iconName).svg")
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private enum MTASubwayStyle {
    static let chateauID = "nyct"

    static let red = RouteHeadingColor(hex: "EE352E")!
    static let green = RouteHeadingColor(hex: "00933C")!
    static let blue = RouteHeadingColor(hex: "0039A6")!
    static let orange = RouteHeadingColor(hex: "FF6319")!
    static let brown = RouteHeadingColor(hex: "996633")!
    static let gray = RouteHeadingColor(hex: "A7A9AC")!
    static let yellow = RouteHeadingColor(hex: "FCCC0A")!
    static let purple = RouteHeadingColor(hex: "B933AD")!
    static let gGreen = RouteHeadingColor(hex: "6CBE45")!

    private static let subwayRouteIDs: Set<String> = [
        "A", "C", "E", "B", "D", "F", "FX", "M", "G", "J", "Z",
        "L", "N", "Q", "R", "W", "GS", "FS", "H", "1", "2", "3",
        "4", "5", "6", "6X", "7", "7X"
    ]

    static func color(for shortName: String) -> RouteHeadingColor {
        switch shortName.uppercased() {
        case "1", "2", "3": red
        case "4", "5", "6", "6X": green
        case "A", "C", "E": blue
        case "B", "D", "F", "FX", "M": orange
        case "G": gGreen
        case "J", "Z": brown
        case "L", "GS", "FS", "H": gray
        case "N", "Q", "R", "W": yellow
        case "7", "7X": purple
        default: .gray
        }
    }

    static func symbolShortName(for shortName: String) -> String {
        switch shortName.uppercased() {
        case "6X": "6"
        case "7X": "7"
        case "FX": "F"
        case "GS", "FS", "H": "S"
        default: shortName
        }
    }

    static func isSubwayRouteID(_ routeID: String) -> Bool {
        subwayRouteIDs.contains(routeID.uppercased())
    }

    static func isExpress(_ routeID: String) -> Bool {
        routeID.uppercased().hasSuffix("X")
    }

    static func iconURL(for routeID: String) -> URL? {
        let routeID = routeID.uppercased()
        let iconName: String

        switch routeID {
        case "6X": iconName = "6d"
        case "7X": iconName = "7d"
        case "FX": iconName = "fd"
        case "GS", "FS", "H": iconName = "s"
        case "SIR": iconName = "sir"
        default:
            if routeID.hasSuffix("X") {
                iconName = routeID.dropLast().lowercased() + "d"
            } else if isSubwayRouteID(routeID) {
                iconName = routeID.lowercased()
            } else {
                return nil
            }
        }

        return URL(string: "https://maps.catenarymaps.org/mtaicons/\(iconName).svg")
    }
}

private struct SBBRouteLogo: View {
    let text: String
    let foreground: RouteHeadingColor

    private var isICOrIR: Bool {
        (text.hasPrefix("IR") || text.hasPrefix("IC")) && !text.hasPrefix("ICE")
    }

    private var isEC: Bool {
        text == "EC"
    }

    private var logoURL: URL? {
        let fileName: String
        if isEC {
            fileName = "SBB_EC_Logo.svg"
        } else if text.hasPrefix("IR") {
            fileName = "SBB_IR_Logo.svg"
        } else {
            fileName = "SBB_IC_Logo.svg"
        }
        return URL(string: "https://maps.catenarymaps.org/icons/sbb/\(fileName)")
    }

    private var remainingText: String {
        guard isICOrIR else {
            return ""
        }
        return String(text.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        if !isICOrIR && !isEC {
            Text(text)
                .font(.headline.bold())
                .foregroundStyle(foreground.swiftUIColor)
        } else {
            HStack(spacing: 3) {
                RemoteSVGImage(
                    url: logoURL,
                    tintCSS: foreground.cssHex,
                    accessibilityLabel: text
                ) {
                    Text(isEC ? "EC" : String(text.prefix(2)))
                        .font(.headline.bold())
                        .foregroundStyle(foreground.swiftUIColor)
                }
                .frame(width: isEC ? 42.5 : 38.25, height: 15.3)

                if !remainingText.isEmpty {
                    Text(remainingText)
                        .font(.headline.bold())
                        .foregroundStyle(foreground.swiftUIColor)
                        .lineLimit(1)
                }
            }
        }
    }
}

private enum DBFernverkehrLookup {
    private struct FullEntry: Decodable {
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    private static let displayNames: [String: String] = {
        if let compactURL = Bundle.main.url(
            forResource: "fernverkehr_2026_display_names",
            withExtension: "json"
        ),
           let data = try? Data(contentsOf: compactURL),
           let values = try? JSONDecoder().decode([String: String].self, from: data) {
            return values
        }

        // Also understand the original Android asset when it is copied verbatim.
        if let fullURL = Bundle.main.url(
            forResource: "fernverkehr_2026_train_lookup",
            withExtension: "json"
        ),
           let data = try? Data(contentsOf: fullURL),
           let values = try? JSONDecoder().decode([String: [FullEntry]].self, from: data) {
            return values.reduce(into: [:]) { output, item in
                if let displayName = item.value.first?.displayName {
                    output[item.key] = displayName
                }
            }
        }

        return [:]
    }()

    static func displayName(for tripNumberWithoutLeadingZeroes: String) -> String? {
        displayNames[tripNumberWithoutLeadingZeroes]
    }
}

private struct RemoteSVGImage<Placeholder: View>: View {
    let url: URL?
    let tintCSS: String?
    let accessibilityLabel: String
    private let placeholder: Placeholder

    @State private var svgSource: String?

    init(
        url: URL?,
        tintCSS: String? = nil,
        accessibilityLabel: String,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.tintCSS = tintCSS
        self.accessibilityLabel = accessibilityLabel
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let svgSource {
                InlineSVGView(svgSource: svgSource, tintCSS: tintCSS)
            } else {
                placeholder
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .task(id: url?.absoluteString) {
            svgSource = nil
            guard let url else {
                return
            }

            do {
                var request = URLRequest(
                    url: url,
                    cachePolicy: .returnCacheDataElseLoad,
                    timeoutInterval: 20
                )
                request.setValue("image/svg+xml", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let response = response as? HTTPURLResponse,
                   !(200 ... 299).contains(response.statusCode) {
                    return
                }
                guard !Task.isCancelled, let source = String(data: data, encoding: .utf8) else {
                    return
                }
                svgSource = source
            } catch {
                // Keep the agency-specific SwiftUI fallback visible.
            }
        }
    }
}

private struct InlineSVGView: UIViewRepresentable {
    let svgSource: String
    let tintCSS: String?

    final class Coordinator {
        var lastSource: String?
        var lastTint: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = false
        webView.isAccessibilityElement = false
        webView.accessibilityElementsHidden = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastSource != svgSource
                || context.coordinator.lastTint != tintCSS else {
            return
        }

        context.coordinator.lastSource = svgSource
        context.coordinator.lastTint = tintCSS
        webView.loadHTMLString(html, baseURL: nil)
    }

    private var html: String {
        let svg = svgSource
            .replacingOccurrences(
                of: #"(?s)<\?xml.*?\?>"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?s)<!DOCTYPE.*?>"#,
                with: "",
                options: .regularExpression
            )

        let tintRules: String
        if let tintCSS {
            tintRules = """
            svg[fill]:not([fill="none"]), svg [fill]:not([fill="none"]) {
                fill: \(tintCSS) !important;
            }
            svg[stroke]:not([stroke="none"]), svg [stroke]:not([stroke="none"]) {
                stroke: \(tintCSS) !important;
            }
            """
        } else {
            tintRules = ""
        }

        return """
        <!doctype html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <style>
                html, body {
                    width: 100%; height: 100%; margin: 0; padding: 0;
                    overflow: hidden; background: transparent;
                }
                body { display: flex; align-items: center; justify-content: center; }
                svg { display: block; width: 100%; height: 100%; }
                \(tintRules)
            </style>
        </head>
        <body>\(svg)</body>
        </html>
        """
    }
}

private struct RouteHeadingColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let white = RouteHeadingColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let gray = RouteHeadingColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    static let iosAccent = RouteHeadingColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    init?(hex input: String) {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }

        guard value.count == 6 || value.count == 8,
              let raw = UInt64(value, radix: 16) else {
            return nil
        }

        if value.count == 8 {
            self.init(
                red: Double((raw >> 24) & 0xff) / 255,
                green: Double((raw >> 16) & 0xff) / 255,
                blue: Double((raw >> 8) & 0xff) / 255,
                alpha: Double(raw & 0xff) / 255
            )
        } else {
            self.init(
                red: Double((raw >> 16) & 0xff) / 255,
                green: Double((raw >> 8) & 0xff) / 255,
                blue: Double(raw & 0xff) / 255
            )
        }
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var cssHex: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    func darkenedToContrastAgainstWhite(minimumRatio: Double) -> RouteHeadingColor {
        let linearRed = Self.sRGBToLinear(red)
        let linearGreen = Self.sRGBToLinear(green)
        let linearBlue = Self.sRGBToLinear(blue)
        let luminance = Self.luminance(
            red: linearRed,
            green: linearGreen,
            blue: linearBlue
        )
        let contrast = 1.05 / (luminance + 0.05)

        guard contrast < minimumRatio, luminance > 0 else {
            return self
        }

        let targetMaximum = (1.05 / minimumRatio) - 0.05
        let scale = min(max(targetMaximum / luminance, 0), 1)
        return RouteHeadingColor(
            red: Self.linearToSRGB(linearRed * scale),
            green: Self.linearToSRGB(linearGreen * scale),
            blue: Self.linearToSRGB(linearBlue * scale),
            alpha: alpha
        )
    }

    func lightenedToContrastAgainstBlack(minimumRatio: Double) -> RouteHeadingColor {
        let linearRed = Self.sRGBToLinear(red)
        let linearGreen = Self.sRGBToLinear(green)
        let linearBlue = Self.sRGBToLinear(blue)
        let luminance = Self.luminance(
            red: linearRed,
            green: linearGreen,
            blue: linearBlue
        )
        let contrast = (luminance + 0.05) / 0.05

        guard contrast < minimumRatio, luminance < 1 else {
            return self
        }

        let targetMinimum = 0.05 * (minimumRatio - 1)
        let amount = min(max((targetMinimum - luminance) / (1 - luminance), 0), 1)
        return RouteHeadingColor(
            red: Self.linearToSRGB(linearRed + amount * (1 - linearRed)),
            green: Self.linearToSRGB(linearGreen + amount * (1 - linearGreen)),
            blue: Self.linearToSRGB(linearBlue + amount * (1 - linearBlue)),
            alpha: alpha
        )
    }

    private static func sRGBToLinear(_ value: Double) -> Double {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ value: Double) -> Double {
        value <= 0.0031308
            ? 12.92 * value
            : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    private static func luminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

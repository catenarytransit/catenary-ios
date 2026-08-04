import Foundation
import SwiftUI
import UIKit
import WebKit

enum MTASubwayUtils {
    static let chateauID = "nyct"

    private static let subwayRouteIDs: Set<String> = [
        "A", "C", "E", "B", "D", "F", "FX", "M", "G", "J", "Z",
        "L", "N", "Q", "R", "W", "GS", "FS", "H", "1", "2", "3",
        "4", "5", "6", "6X", "7", "7X"
    ]

    static func color(for routeID: String) -> Color {
        switch routeID.uppercased() {
        case "1", "2", "3": return color(0xEE352E)
        case "4", "5", "6", "6X": return color(0x00933C)
        case "A", "C", "E": return color(0x0039A6)
        case "B", "D", "F", "FX", "M": return color(0xFF6319)
        case "G": return color(0x6CBE45)
        case "J", "Z": return color(0x996633)
        case "L", "GS", "FS", "H": return color(0xA7A9AC)
        case "N", "Q", "R", "W": return color(0xFCCC0A)
        case "7", "7X": return color(0xB933AD)
        default: return .gray
        }
    }

    static func symbolShortName(for routeID: String) -> String {
        switch routeID.uppercased() {
        case "6X": return "6"
        case "7X": return "7"
        case "FX": return "F"
        case "GS", "FS", "H": return "S"
        default: return routeID
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

    private static func color(_ rgb: UInt32) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255
        )
    }
}

struct MTASubwayIcon: View {
    let routeID: String
    var size: CGFloat = 24

    var body: some View {
        TransitRemoteSVGImage(
            url: MTASubwayUtils.iconURL(for: routeID),
            accessibilityLabel: routeID
        ) {
            ZStack {
                Circle()
                    .fill(MTASubwayUtils.color(for: routeID))
                Text(MTASubwayUtils.symbolShortName(for: routeID))
                    .font(.system(size: size * 0.58, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
    }
}

enum NationalRailUtils {
    static let chateauID = "nationalrailuk"

    struct AgencyInfo: Sendable {
        let name: String
        let iconName: String?
    }

    private static let agenciesByID: [String: AgencyInfo] = [
        "GW": AgencyInfo(name: "Great Western Railway", iconName: "GreaterWesternRailway.svg"),
        "GWR": AgencyInfo(name: "Great Western Railway", iconName: "GreaterWesternRailway.svg"),
        "SW": AgencyInfo(name: "South Western Railway", iconName: "SouthWesternRailway.svg"),
        "SN": AgencyInfo(name: "Southern", iconName: "SouthernIcon.svg"),
        "CC": AgencyInfo(name: "c2c", iconName: "c2c_logo.svg"),
        "LE": AgencyInfo(name: "Greater Anglia", iconName: nil),
        "CH": AgencyInfo(name: "Chiltern Railways", iconName: nil),
        "VT": AgencyInfo(name: "Avanti West Coast", iconName: nil),
        "HT": AgencyInfo(name: "Hull Trains", iconName: nil),
        "GN": AgencyInfo(name: "Great Northern", iconName: nil),
        "TL": AgencyInfo(name: "Thameslink", iconName: nil),
        "LO": AgencyInfo(name: "London Overground", iconName: "uk-london-overground.svg"),
        "AW": AgencyInfo(name: "Transport for Wales", iconName: nil),
        "SR": AgencyInfo(name: "ScotRail", iconName: nil),
        "GR": AgencyInfo(name: "London North Eastern Railway", iconName: nil),
        "EM": AgencyInfo(name: "East Midlands Railway", iconName: nil),
        "LM": AgencyInfo(name: "West Midlands Railway", iconName: nil),
        "SE": AgencyInfo(name: "Southeastern", iconName: nil),
        "XC": AgencyInfo(name: "CrossCountry", iconName: nil),
        "XR": AgencyInfo(name: "Elizabeth Line", iconName: "Elizabeth_line_roundel.svg")
    ]

    private static let agenciesByName: [String: AgencyInfo] = {
        var result: [String: AgencyInfo] = [:]
        for info in agenciesByID.values {
            result[normalize(info.name)] = info
        }
        result["gwr"] = agenciesByID["GWR"]
        return result
    }()

    static func agencyInfo(agencyID: String?, agencyName: String?) -> AgencyInfo? {
        if let agencyID, let value = agenciesByID[agencyID.uppercased()] {
            return value
        }
        if let agencyName, let value = agenciesByName[normalize(agencyName)] {
            return value
        }
        return nil
    }

    static func resolvedAgencyName(agencyID: String?, agencyName: String?) -> String? {
        agencyInfo(agencyID: agencyID, agencyName: agencyName)?.name
            ?? nonBlank(agencyName)
    }

    static func agencyIconURL(agencyID: String?, agencyName: String?) -> URL? {
        guard let iconName = agencyInfo(agencyID: agencyID, agencyName: agencyName)?.iconName else {
            return nil
        }
        return URL(string: "https://maps.catenarymaps.org/agencyicons/\(iconName)")
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

struct NationalRailAgencyLabel: View {
    let agencyID: String?
    let agencyName: String?
    var compact = false

    var body: some View {
        if let resolvedName = NationalRailUtils.resolvedAgencyName(
            agencyID: agencyID,
            agencyName: agencyName
        ) {
            HStack(spacing: 4) {
                if let iconURL = NationalRailUtils.agencyIconURL(
                    agencyID: agencyID,
                    agencyName: agencyName
                ) {
                    TransitRemoteSVGImage(url: iconURL, accessibilityLabel: resolvedName) {
                        Image(systemName: "train.side.front.car")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: compact ? 14 : 16, height: compact ? 14 : 16)
                }

                Text(resolvedName)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct TransitRemoteSVGImage<Placeholder: View>: View {
    let url: URL?
    let accessibilityLabel: String
    private let placeholder: Placeholder

    @State private var svgSource: String?

    init(
        url: URL?,
        accessibilityLabel: String,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.accessibilityLabel = accessibilityLabel
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let svgSource {
                TransitInlineSVGView(svgSource: svgSource)
            } else {
                placeholder
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .task(id: url?.absoluteString) {
            svgSource = nil
            guard let url else { return }

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
                guard !Task.isCancelled,
                      let source = String(data: data, encoding: .utf8) else {
                    return
                }
                svgSource = source
            } catch {
                // Retain the SwiftUI fallback if the remote icon cannot be loaded.
            }
        }
    }
}

private struct TransitInlineSVGView: UIViewRepresentable {
    let svgSource: String

    final class Coordinator {
        var lastSource: String?
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
        guard context.coordinator.lastSource != svgSource else { return }
        context.coordinator.lastSource = svgSource
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
            </style>
        </head>
        <body>\(svg)</body>
        </html>
        """
    }
}

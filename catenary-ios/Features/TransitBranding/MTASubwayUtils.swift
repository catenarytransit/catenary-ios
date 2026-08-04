import Foundation
import SwiftUI

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

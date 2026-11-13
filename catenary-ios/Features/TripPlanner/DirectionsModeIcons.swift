import SwiftUI

/// Minimal SVG path-data parser covering the M/L/H/V/C/Z commands used by the bundled mode icons below.
/// Rebuilding them as native `Path`s (instead of rendering raw SVG `currentColor` fills) lets them tint
/// with the ambient foreground color like any other SwiftUI glyph.
func svgPath(_ d: String) -> Path {
    var commands: [(Character, [Double])] = []
    var pendingCommand: Character?
    var numbers: [Double] = []
    var current = ""
    func flushNumber() {
        guard !current.isEmpty else { return }
        numbers.append(Double(current) ?? 0)
        current = ""
    }
    for char in d {
        if char.isLetter {
            flushNumber()
            if let pendingCommand { commands.append((pendingCommand, numbers)) }
            pendingCommand = char
            numbers = []
        } else if char == "-" || char == "+" {
            if !current.isEmpty { flushNumber() }
            current.append(char)
        } else if char == "." {
            if current.contains(".") { flushNumber() }
            current.append(char)
        } else if char.isNumber {
            current.append(char)
        } else {
            flushNumber()
        }
    }
    flushNumber()
    if let pendingCommand { commands.append((pendingCommand, numbers)) }

    var path = Path()
    var point = CGPoint.zero
    var start = CGPoint.zero
    for (command, values) in commands {
        var remaining = values
        switch command {
        case "M":
            while remaining.count >= 2 {
                point = CGPoint(x: remaining.removeFirst(), y: remaining.removeFirst())
                path.move(to: point); start = point
            }
        case "L":
            while remaining.count >= 2 {
                point = CGPoint(x: remaining.removeFirst(), y: remaining.removeFirst())
                path.addLine(to: point)
            }
        case "H":
            while remaining.count >= 1 {
                point = CGPoint(x: remaining.removeFirst(), y: point.y)
                path.addLine(to: point)
            }
        case "V":
            while remaining.count >= 1 {
                point = CGPoint(x: point.x, y: remaining.removeFirst())
                path.addLine(to: point)
            }
        case "C":
            while remaining.count >= 6 {
                let control1 = CGPoint(x: remaining.removeFirst(), y: remaining.removeFirst())
                let control2 = CGPoint(x: remaining.removeFirst(), y: remaining.removeFirst())
                point = CGPoint(x: remaining.removeFirst(), y: remaining.removeFirst())
                path.addCurve(to: point, control1: control1, control2: control2)
            }
        case "Z", "z":
            path.closeSubpath(); point = start
        default:
            break
        }
    }
    return path
}

/// Ported from catenary-compose's `assets/directions/*.svg` (the Android app's SBB-pictogram-style mode
/// icons), redrawn as vector paths in their original 24x24 viewBox.
struct DirectionsModeGlyph: View {
    let paths: [String]
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            for d in paths {
                context.fill(svgPath(d).applying(transform), with: .color(.white))
            }
        }
    }
}

extension DirectionsModeGlyph {
    static let bus = DirectionsModeGlyph(paths: [
        "M6.375 8.25H3V7.5H18.074C18.685 7.5 19.219 7.91 19.378 8.5L20.954 14.369C20.985 14.483 21 14.601 21 14.719V18.525C21 18.856 20.731 19.125 20.4 19.125H13.424C13.093 19.125 12.824 18.856 12.824 18.525C12.824 18.521 12.824 18.518 12.824 18.514C12.825 18.493 12.825 18.471 12.825 18.45C12.825 16.546 11.279 15 9.375 15C7.471 15 5.925 16.546 5.925 18.45C5.925 18.471 5.925 18.493 5.926 18.514C5.926 18.518 5.926 18.521 5.926 18.525C5.926 18.856 5.657 19.125 5.326 19.125H3V13.5H6.375C6.582 13.5 6.75 13.332 6.75 13.125V8.625C6.75 8.418 6.582 8.25 6.375 8.25ZM17.438 14.625C17.438 14.832 17.606 15 17.813 15H19.858C20.065 15 20.233 14.832 20.233 14.625C20.233 14.592 20.229 14.559 20.22 14.528L18.634 8.62C18.564 8.358 18.326 8.176 18.054 8.176H18.038C17.707 8.176 17.438 8.445 17.438 8.776V14.625ZM15.488 14.475C15.488 14.806 15.757 15.075 16.088 15.075C16.419 15.075 16.688 14.806 16.688 14.475V8.775C16.688 8.444 16.419 8.175 16.088 8.175C15.757 8.175 15.488 8.444 15.488 8.775V14.475ZM13.538 14.475C13.538 14.806 13.807 15.075 14.138 15.075C14.469 15.075 14.738 14.806 14.738 14.475V8.775C14.738 8.444 14.469 8.175 14.138 8.175C13.807 8.175 13.538 8.444 13.538 8.775V14.475ZM7.5 13.125C7.5 13.332 7.668 13.5 7.875 13.5H12.412C12.619 13.5 12.787 13.332 12.787 13.125V8.625C12.787 8.418 12.619 8.25 12.412 8.25H7.875C7.668 8.25 7.5 8.418 7.5 8.625V13.125Z",
        "M9.35059 15.847C10.7996 15.847 11.9756 17.023 11.9756 18.472C11.9756 19.921 10.7996 21.097 9.35059 21.097C7.90159 21.097 6.72559 19.921 6.72559 18.472C6.72659 17.023 7.90159 15.847 9.35059 15.847ZM9.35059 19.916C10.1786 19.916 10.8506 19.244 10.8506 18.416C10.8506 17.588 10.1786 16.916 9.35059 16.916C8.52259 16.916 7.85059 17.588 7.85059 18.416C7.85159 19.244 8.52359 19.916 9.35059 19.916Z"
    ])
    static let metro = DirectionsModeGlyph(paths: [
        "M21 20.25H3V21H21V20.25Z",
        "M20.422 8.75499C20.356 8.03599 20.058 7.57599 19.22 7.57599H13.81H3V8.25099H5.401C5.608 8.25099 5.776 8.41899 5.776 8.62599V14.185C5.776 14.392 5.608 14.56 5.401 14.56H3V19.5H20.624C20.831 19.5 20.999 19.332 20.999 19.125V14.844C20.999 14.785 20.422 8.75499 20.422 8.75499ZM7.713 18.172C7.713 18.491 7.454 18.749 7.136 18.749C6.817 18.749 6.559 18.49 6.559 18.172V8.75399C6.559 8.43499 6.818 8.17699 7.136 8.17699C7.455 8.17699 7.713 8.43599 7.713 8.75399V18.172ZM9.65 18.172C9.65 18.491 9.391 18.749 9.073 18.749C8.754 18.749 8.496 18.49 8.496 18.172V8.75399C8.496 8.43499 8.755 8.17699 9.073 8.17699C9.392 8.17699 9.65 8.43599 9.65 8.75399V18.172ZM14.98 14.185C14.98 14.392 14.812 14.56 14.605 14.56H10.807C10.6 14.56 10.432 14.392 10.432 14.185V8.62599C10.432 8.41899 10.6 8.25099 10.807 8.25099H14.605C14.812 8.25099 14.98 8.41899 14.98 8.62599V14.185ZM19.949 14.527L16.015 14.559C15.808 14.559 15.64 14.391 15.64 14.184V8.62599C15.64 8.41899 15.808 8.25099 16.015 8.25099H19.479C19.686 8.25099 19.827 8.38399 19.854 8.62599L20.294 14.156C20.314 14.372 20.156 14.527 19.949 14.527Z"
    ])
    static let tram = DirectionsModeGlyph(paths: [
        "M10.42 4.18599C10.355 4.12099 10.318 4.03299 10.318 3.94099C10.318 3.74899 10.473 3.59399 10.665 3.59399C10.757 3.59399 10.845 3.62999 10.91 3.69599L14.791 7.57699H17.877C18.429 7.57699 18.917 7.93799 19.079 8.46699L20.973 14.67C20.991 14.726 21 14.785 21 14.844V17.55C21 17.757 20.832 17.925 20.625 17.925H3.00098V13.5H6.63798C6.84498 13.5 7.01298 13.332 7.01298 13.125V8.62499C7.01298 8.41799 6.84498 8.24999 6.63798 8.24999H3.00098V7.57599H13.811L10.42 4.18599ZM17.25 14.626C17.25 14.833 17.418 15.001 17.625 15.001H19.843C20.05 15.001 20.218 14.833 20.218 14.626C20.218 14.589 20.212 14.552 20.202 14.517L18.388 8.57499C18.316 8.33799 18.097 8.17699 17.85 8.17699H17.813C17.502 8.17699 17.251 8.42899 17.251 8.73899L17.25 14.626ZM15.432 14.513C15.432 14.823 15.684 15.075 15.994 15.075C16.305 15.075 16.557 14.823 16.557 14.513V8.73899C16.557 8.42799 16.305 8.17699 15.994 8.17699C15.684 8.17699 15.432 8.42899 15.432 8.73899V14.513ZM12.938 8.62599C12.938 8.41899 12.77 8.25099 12.563 8.25099H8.06298C7.85598 8.25099 7.68798 8.41899 7.68798 8.62599V13.126C7.68798 13.333 7.85598 13.501 8.06298 13.501H12.563C12.77 13.501 12.938 13.333 12.938 13.126V8.62599ZM13.613 8.73899V14.513C13.613 14.823 13.865 15.075 14.175 15.075C14.486 15.075 14.737 14.823 14.737 14.513V8.73899C14.737 8.42799 14.485 8.17699 14.175 8.17699C13.865 8.17599 13.613 8.42799 13.613 8.73899Z",
        "M12.3486 18.675H16.1276C15.8166 19.445 15.0686 19.95 14.2376 19.95C13.4076 19.95 12.6596 19.446 12.3486 18.675Z",
        "M7.84863 18.675H11.6286C11.3176 19.445 10.5696 19.95 9.73863 19.95C8.90763 19.95 8.15963 19.446 7.84863 18.675Z",
        "M21 20.325H3V21H21V20.325Z",
        "M21 3H3V3.375H21V3Z"
    ])
    static let train = DirectionsModeGlyph(paths: [
        "M20.711 18.862C20.918 18.862 21.086 18.694 21.086 18.487C21.086 18.469 21.085 18.451 21.082 18.434L20.763 16.198H16.874V18.862H20.711Z",
        "M11.634 8.19299H3.00002V7.49999H10.05L7.83702 5.99999L12 3.63699L16.137 5.99999H16.162L13.949 7.49999H18.545C19.105 7.49999 19.58 7.91199 19.659 8.46599L20.662 15.488H2.99902V11.776H11.633C11.835 11.776 11.999 11.612 11.999 11.41C11.999 11.208 11.835 11.044 11.633 11.044H2.99902V10.35H11.633C11.835 10.35 11.999 10.186 11.999 9.98399C11.999 9.78199 11.835 9.61799 11.633 9.61799H2.99902V8.92499H11.633C11.835 8.92499 11.999 8.76099 11.999 8.55899C11.999 8.35699 11.835 8.19299 11.634 8.19299ZM16.649 11.4C16.649 11.607 16.817 11.775 17.024 11.775H18.979C19.186 11.775 19.354 11.607 19.354 11.4C19.354 11.382 19.353 11.364 19.35 11.347L18.945 8.51599C18.919 8.33099 18.76 8.19399 18.574 8.19399H17.023C16.816 8.19399 16.648 8.36199 16.648 8.56899L16.649 11.4ZM12.679 7.49999L14.804 6.05999L11.998 4.45799L9.18502 6.05399L11.319 7.49999H12.679Z",
        "M7.79102 18.021C7.79102 16.965 8.64802 16.109 9.70402 16.109C10.759 16.109 11.616 16.966 11.616 18.021C11.616 19.077 10.759 19.934 9.70402 19.934C8.64702 19.933 7.79102 19.077 7.79102 18.021Z",
        "M12.2988 18.021C12.2988 16.965 13.1558 16.109 14.2118 16.109C15.2678 16.109 16.1238 16.966 16.1238 18.021C16.1238 19.077 15.2668 19.934 14.2118 19.934C13.1558 19.933 12.2988 19.077 12.2988 18.021Z",
        "M21 3V3.375H3V3H21Z",
        "M3 21V20.288H21V21H3Z",
        "M3 16.313V16.2H7.125V18.862H3V16.313Z"
    ])
}

enum DirectionsModeCategory {
    case bus, metro, tram, train, other
}

extension DirectionsLeg {
    /// Matches the Android app's LegModeIcon/legModeLabel category rules, including the routeType fallback.
    var modeCategory: DirectionsModeCategory {
        let upper = mode.uppercased()
        if ["BUS", "COACH"].contains(upper) || routeType == 3 { return .bus }
        if ["SUBWAY", "METRO"].contains(upper) || routeType == 1 { return .metro }
        if ["TRAM", "LIGHT_RAIL"].contains(upper) || routeType == 0 { return .tram }
        if ["RAIL", "TRAIN", "REGIONAL_RAIL", "HIGH_SPEED_RAIL"].contains(upper) || routeType == 2 { return .train }
        return .other
    }
}

/// SBB-style glyphs for bus/metro/tram/train; everything else (walk, bike, ferry, unknown) keeps its SF Symbol.
struct LegModeIcon: View {
    let leg: DirectionsLeg
    var preview = false
    var body: some View {
        switch leg.modeCategory {
        case .bus: DirectionsModeGlyph.bus.frame(width: preview ? 16 : 24, height: preview ? 16 : 24)
        case .metro: DirectionsModeGlyph.metro.frame(width: preview ? 16 : 24, height: preview ? 16 : 24)
        case .tram: DirectionsModeGlyph.tram.frame(width: preview ? 16 : 24, height: preview ? 16 : 24)
        case .train: DirectionsModeGlyph.train.frame(width: preview ? 16 : 24, height: preview ? 16 : 24)
        case .other:
            Image(systemName: leg.systemImage)
                .font(.system(size: preview ? 14 : (leg.street ? 18 : 24)))
        }
    }
}

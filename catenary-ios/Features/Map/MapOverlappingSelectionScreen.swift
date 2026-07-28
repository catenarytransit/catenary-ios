import SwiftUI

/// SwiftUI counterpart of Compose's overlapping-object selection screen.
///
/// The selection destination is replaced rather than pushed. This keeps the
/// chooser as an implementation detail: Back returns to the screen that was
/// open before the map tap instead of returning to a stale chooser.
struct MapOverlappingSelectionScreen: View {
    let options: [MapSelectionOption]

    @EnvironmentObject private var viewObject: viewObject

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                Text(selectionCountTitle)
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)

                if !vehicles.isEmpty {
                    sectionHeader("Vehicles")

                    ForEach(vehicles) { option in
                        selectionButton(for: option) {
                            VehicleSelectionRow(selector: option.data)
                        }
                    }
                }

                if !stations.isEmpty {
                    sectionHeader("Stations")

                    ForEach(stations) { option in
                        selectionButton(for: option) {
                            StationSelectionRow(selector: option.data)
                        }
                    }
                }

                if !stops.isEmpty {
                    sectionHeader("Stops")

                    ForEach(stops) { option in
                        selectionButton(for: option) {
                            StopSelectionRow(selector: option.data)
                        }
                    }
                }

                if !routes.isEmpty {
                    Text("Lines")
                        .font(.title2)
                        .padding(.top, 6)

                    ForEach(SelectionRouteCategory.displayOrder, id: \.self) { category in
                        let categoryRoutes = routes.filter { $0.data.routeCategory == category }

                        if !categoryRoutes.isEmpty {
                            Text(category.title)
                                .font(.headline)
                                .foregroundStyle(category.colour)
                                .padding(.top, 2)

                            ForEach(categoryRoutes) { option in
                                selectionButton(for: option) {
                                    RouteSelectionRow(selector: option.data)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 64)
        }
    }

    private var selectionCountTitle: String {
        "\(options.count) \(options.count == 1 ? "item" : "items") selected"
    }

    private var vehicles: [MapSelectionOption] {
        unique(options.filter { $0.data.selectionKind == .vehicle })
    }

    private var stations: [MapSelectionOption] {
        unique(options.filter { $0.data.selectionKind == .station })
    }

    private var stops: [MapSelectionOption] {
        unique(options.filter { $0.data.selectionKind == .stop })
    }

    private var routes: [MapSelectionOption] {
        unique(options.filter { $0.data.selectionKind == .route })
    }

    private func unique(_ candidates: [MapSelectionOption]) -> [MapSelectionOption] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.top, 8)
    }

    private func selectionButton<Label: View>(
        for option: MapSelectionOption,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            viewObject.replaceTop(with: option.destination)
        } label: {
            label()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct VehicleSelectionRow: View {
    let selector: MapSelectionSelector

    var body: some View {
        if case let .vehicle(
            _, _, _, headsign, tripLabel, colour, routeShortName, routeLongName,
            routeType, tripShortName, textColour, _, _, _, _
        ) = selector {
            VStack(alignment: .leading, spacing: 2) {
                routeName(
                    shortName: routeShortName,
                    longName: routeLongName,
                    colour: Color(catenaryHex: colour) ?? modeColour(routeType)
                )

                HStack(spacing: 4) {
                    if let runNumber = nonEmpty(tripShortName) ?? nonEmpty(tripLabel) {
                        Text(runNumber)
                            .font(.subheadline)
                            .foregroundStyle(Color(catenaryHex: textColour) ?? .white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Color(catenaryHex: colour) ?? modeColour(routeType),
                                in: .rect(cornerRadius: 4)
                            )
                    }

                    if let headsign = nonEmpty(headsign) {
                        Text("›")
                            .foregroundStyle(.secondary)

                        Text(headsign)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                }
            }
            .selectionSurface()
        }
    }

    private func routeName(
        shortName: String?,
        longName: String?,
        colour: Color
    ) -> some View {
        let shortName = nonEmpty(shortName)
        let longName = nonEmpty(longName)

        return Group {
            if let shortName, let longName, !longName.localizedCaseInsensitiveContains(shortName) {
                Text("\(Text(shortName).bold()) \(longName)")
            } else {
                Text(longName ?? shortName ?? "Unknown line")
                    .bold()
            }
        }
        .font(.body)
        .foregroundStyle(colour)
        .lineLimit(2)
    }
}

private struct StationSelectionRow: View {
    let selector: MapSelectionSelector

    var body: some View {
        if case let .osmStation(_, name, modeType, _, _) = selector {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(stationModeName(modeType))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .selectionSurface()
        }
    }

    private func stationModeName(_ modeType: String) -> String {
        switch modeType.lowercased() {
        case "subway", "metro": return "Metro"
        case "rail", "train": return "Rail"
        case "tram", "light_rail": return "Tram"
        default: return modeType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct StopSelectionRow: View {
    let selector: MapSelectionSelector

    var body: some View {
        if case let .stop(_, _, stopName) = selector {
            Text(stopName)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .selectionSurface()
        }
    }
}

private struct RouteSelectionRow: View {
    let selector: MapSelectionSelector

    var body: some View {
        if case let .route(_, _, colour, name, routeType) = selector {
            Text(nonEmpty(name) ?? "Unnamed line")
                .font(.body.weight(.bold))
                .foregroundStyle(Color(catenaryHex: colour) ?? modeColour(routeType))
                .lineLimit(2)
                .selectionSurface()
        }
    }
}

private enum MapSelectionKind: Equatable {
    case vehicle
    case station
    case stop
    case route
}

private enum SelectionRouteCategory: Hashable {
    case rail
    case metro
    case tram
    case other
    case bus

    static let displayOrder: [SelectionRouteCategory] = [.rail, .metro, .tram, .other, .bus]

    var title: String {
        switch self {
        case .rail: return "Train"
        case .metro: return "Metro"
        case .tram: return "Tram"
        case .other: return "Other"
        case .bus: return "Bus"
        }
    }

    var colour: Color {
        switch self {
        case .rail: return .railCategory
        case .metro: return .metroCategory
        case .tram: return .tramCategory
        case .other: return .otherCategory
        case .bus: return .busCategory
        }
    }
}

private extension MapSelectionSelector {
    var selectionKind: MapSelectionKind {
        switch self {
        case .vehicle: return .vehicle
        case .osmStation: return .station
        case .stop: return .stop
        case .route: return .route
        }
    }

    var routeCategory: SelectionRouteCategory? {
        guard case let .route(_, _, _, _, routeType) = self else { return nil }

        switch routeType {
        case 2, 100, 101, 102, 103, 106, 107:
            return .rail
        case 1, 5, 7, 12, 900:
            return .metro
        case 0:
            return .tram
        case 3, 11, 700:
            return .bus
        default:
            return .other
        }
    }
}

private extension View {
    func selectionSurface() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Color(uiColor: .secondarySystemBackground).opacity(0.8),
                in: .rect(cornerRadius: 6)
            )
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

private func modeColour(_ routeType: Int?) -> Color {
    switch StopTransitMode.from(routeType: routeType) {
    case .rail: return .railCategory
    case .metro: return .metroCategory
    case .bus: return .busCategory
    case .other: return .otherCategory
    }
}

private extension Color {
    init?(catenaryHex value: String) {
        let normalized = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard normalized.count == 6, let rgb = UInt64(normalized, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}


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
            LazyVStack(alignment: .leading, spacing: 8) {
                Text("Choose an item")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Multiple objects overlap at this point on the map.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                ForEach(options) { option in
                    Button {
                        viewObject.replaceTop(with: option.destination)
                    } label: {
                        MapSelectionRow(selector: option.data)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

private struct MapSelectionRow: View {
    let selector: MapSelectionSelector

    var body: some View {
        HStack(spacing: 12) {
            leadingView
                .frame(minWidth: 44, maxWidth: 44, minHeight: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .contentShape(Rectangle())
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary)
        }
    }

    @ViewBuilder
    private var leadingView: some View {
        switch selector {
        case .stop:
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

        case let .route(_, _, colour, name, routeType):
            routeBadge(
                label: name,
                colour: colour,
                textColour: "FFFFFF",
                fallback: modeColour(routeType)
            )

        case let .vehicle(
            _, _, _, _, tripLabel, colour, routeShortName, routeLongName,
            routeType, tripShortName, textColour, _, _, _, _
        ):
            routeBadge(
                label: routeShortName ?? tripShortName ?? tripLabel ?? routeLongName,
                colour: colour,
                textColour: textColour,
                fallback: modeColour(routeType)
            )

        case let .osmStation(_, _, modeType, _, _):
            Image(systemName: modeImage(modeType))
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch selector {
        case let .stop(_, _, stopName):
            return stopName
        case let .route(_, routeID, _, name, _):
            return nonEmpty(name) ?? routeID
        case let .vehicle(
            _, _, _, headsign, tripLabel, _, routeShortName, routeLongName,
            _, tripShortName, _, _, _, _, _
        ):
            return nonEmpty(routeShortName)
                ?? nonEmpty(tripShortName)
                ?? nonEmpty(tripLabel)
                ?? nonEmpty(routeLongName)
                ?? nonEmpty(headsign)
                ?? "Vehicle"
        case let .osmStation(_, name, _, _, _):
            return name
        }
    }

    private var subtitle: String {
        switch selector {
        case let .stop(_, stopID, _):
            return stopID
        case let .route(_, routeID, _, _, routeType):
            return [modeName(routeType), nonEmpty(routeID)].compactMap { $0 }.joined(separator: " • ")
        case let .vehicle(_, vehicleID, routeID, headsign, _, _, _, _, routeType, _, _, _, _, _, _):
            return [modeName(routeType), nonEmpty(headsign), nonEmpty(vehicleID), nonEmpty(routeID)]
                .compactMap { $0 }
                .joined(separator: " • ")
        case let .osmStation(_, _, modeType, _, _):
            return modeType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var detail: String? {
        guard case let .vehicle(
            _, _, _, _, _, _, _, _, _, tripShortName, _, _, tripID, startTime, startDate
        ) = selector else { return nil }

        return [nonEmpty(tripShortName), nonEmpty(tripID), nonEmpty(startDate), nonEmpty(startTime)]
            .compactMap { $0 }
            .joined(separator: " • ")
    }

    private func routeBadge(
        label: String?,
        colour: String,
        textColour: String,
        fallback: Color
    ) -> some View {
        Text(nonEmpty(label).map { String($0.prefix(6)) } ?? "—")
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .foregroundStyle(Color(catenaryHex: textColour) ?? .white)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Color(catenaryHex: colour) ?? fallback, in: .rect(cornerRadius: 7))
    }

    private func modeImage(_ modeType: String) -> String {
        switch modeType.lowercased() {
        case "rail", "train": return "tram.fill.tunnel"
        case "subway", "metro", "tram", "light_rail": return "lightrail.fill"
        case "bus", "trolleybus": return "bus.fill"
        case "ferry": return "ferry.fill"
        default: return "building.2.fill"
        }
    }

    private func modeName(_ routeType: Int?) -> String? {
        guard let routeType else { return nil }
        return StopTransitMode.from(routeType: routeType).title
    }

    private func modeColour(_ routeType: Int?) -> Color {
        switch StopTransitMode.from(routeType: routeType) {
        case .rail: return .railCategory
        case .metro: return .metroCategory
        case .bus: return .busCategory
        case .other: return .otherCategory
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
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

import SwiftUI

struct StationDepartureRow: View {
    let event: StopEvent
    let routeInfo: StopRouteInfo?
    let agency: StopAgencyInfo?
    let timezoneID: String?
    let now: Date

    @EnvironmentObject private var viewObject: viewObject

    private var mode: StopTransitMode {
        .from(routeType: routeInfo?.routeType ?? event.routeType)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                viewObject.push(.route(chateauID: event.chateau, routeID: event.routeId))
            } label: {
                StopRouteBadge(
                    shortName: routeInfo?.shortName ?? event.tripShortName,
                    longName: routeInfo?.longName,
                    colorHex: routeInfo?.color,
                    textColorHex: routeInfo?.textColor,
                    mode: mode
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open route")

            Button(action: openTrip) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.finalStationName ?? event.headsign ?? "Departure")
                            .font(mode == .rail ? .headline : .subheadline.weight(.semibold))
                            .foregroundStyle(event.isCancelled ? .red : .primary)
                            .strikethrough(event.isCancelled)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        metadataLine
                    }

                    StopDepartureTimeView(
                        event: event,
                        timezoneID: timezoneID,
                        now: now
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(event.tripId == nil && event.routeId.isEmpty)
        }
        .padding(.vertical, mode == .rail ? 11 : 9)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var metadataLine: some View {
        let values = [
            event.tripShortName,
            event.platformStringRealtime.map { "Platform \($0)" },
            event.vehicleNumber,
            mode == .rail ? agency?.agencyName : nil
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        if !values.isEmpty {
            Text(values.joined(separator: "  •  "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func openTrip() {
        viewObject.push(.singleTrip(
            chateauID: event.chateau,
            tripID: event.tripId,
            routeID: event.routeId,
            startTime: nil,
            startDate: event.serviceDate?.replacingOccurrences(of: "-", with: ""),
            vehicleID: event.vehicleNumber,
            routeType: event.routeType ?? routeInfo?.routeType
        ))
    }
}

private struct StopDepartureTimeView: View {
    let event: StopEvent
    let timezoneID: String?
    let now: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let scheduled = event.scheduledTime,
               let realtime = event.realtimeTime,
               scheduled != realtime {
                Text(StopDateFormatting.time(epochSeconds: scheduled, timezoneID: timezoneID))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .strikethrough()
            }

            Text(StopDateFormatting.time(epochSeconds: event.effectiveTime, timezoneID: timezoneID))
                .font(.headline.monospacedDigit())
                .foregroundStyle(event.isCancelled ? .red : .primary)

            if let countdown = StopDateFormatting.countdown(
                epochSeconds: event.effectiveTime,
                relativeTo: now
            ) {
                Text(countdown)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let delay = StopDateFormatting.delay(event: event) {
                Text(delay)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(StopDateFormatting.delayColor(event: event))
            }
        }
        .frame(minWidth: 70, alignment: .trailing)
    }
}

private struct StopRouteBadge: View {
    let shortName: String?
    let longName: String?
    let colorHex: String?
    let textColorHex: String?
    let mode: StopTransitMode

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(StopHexColor.color(textColorHex, fallback: .white))
            .padding(.horizontal, 7)
            .frame(width: 48)
            .frame(minHeight: mode == .rail ? 30 : 28)
            .background(
                StopHexColor.color(colorHex, fallback: fallbackColor),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }

    private var label: String {
        if let shortName, !shortName.isEmpty { return shortName }
        if let longName, !longName.isEmpty { return String(longName.prefix(5)) }
        return mode == .rail ? "Rail" : "—"
    }

    private var fallbackColor: Color {
        switch mode {
        case .rail: return .railCategory
        case .metro: return .metroCategory
        case .bus: return .busCategory
        case .other: return .otherCategory
        }
    }
}

enum StopDateFormatting {
    static func time(epochSeconds: Int64?, timezoneID: String?) -> String {
        guard let epochSeconds else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    static func day(epochSeconds: Int64, timezoneID: String?) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        return calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    static func dayTitle(date: Date, timezoneID: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    static func clock(date: Date, timezoneID: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    static func countdown(epochSeconds: Int64?, relativeTo now: Date) -> String? {
        guard let epochSeconds else { return nil }
        let seconds = epochSeconds - Int64(now.timeIntervalSince1970)
        guard seconds >= -60, seconds < 3600 else { return nil }
        if seconds < 30 { return "Due" }
        return "in \(max(1, Int(ceil(Double(seconds) / 60.0)))) min"
    }

    static func delay(event: StopEvent) -> String? {
        let seconds = delaySeconds(event: event)
        guard let seconds, abs(seconds) >= 30 else { return nil }
        let minutes = Int((Double(seconds) / 60.0).rounded())
        return minutes > 0 ? "+\(minutes) min" : "\(minutes) min"
    }

    static func delayColor(event: StopEvent) -> Color {
        let seconds = delaySeconds(event: event) ?? 0
        return seconds < 0 ? .green : .orange
    }

    private static func delaySeconds(event: StopEvent) -> Int64? {
        if let delay = event.delaySeconds { return delay }
        guard let scheduled = event.scheduledTime, let realtime = event.realtimeTime else { return nil }
        return realtime - scheduled
    }
}

private enum StopHexColor {
    static func color(_ value: String?, fallback: Color) -> Color {
        guard var value, !value.isEmpty else { return fallback }
        value = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let rgb = Int(value, radix: 16) else { return fallback }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

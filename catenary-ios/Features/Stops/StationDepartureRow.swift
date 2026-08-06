import SwiftUI

struct StationDepartureRow: View {
    let event: StopEvent
    let routeInfo: StopRouteInfo?
    let agency: StopAgencyInfo?
    let timezoneID: String?
    let now: Date
    let layout: StopDepartureLayout
    let trainDisplayName: String?

    @EnvironmentObject private var viewObject: viewObject
    @AppStorage("showCountdownsUnder1h") private var showCountdownsUnder1h = false
    @AppStorage("showLocalTransitCountdowns") private var showLocalTransitCountdowns = false

    init(
        event: StopEvent,
        routeInfo: StopRouteInfo?,
        agency: StopAgencyInfo?,
        timezoneID: String?,
        now: Date,
        layout: StopDepartureLayout = .regular,
        trainDisplayName: String? = nil
    ) {
        self.event = event
        self.routeInfo = routeInfo
        self.agency = agency
        self.timezoneID = timezoneID
        self.now = now
        self.layout = layout
        self.trainDisplayName = trainDisplayName
    }

    private var mode: StopTransitMode {
        .from(routeType: routeInfo?.routeType ?? event.routeType)
    }

    private var showsRouteBadge: Bool {
        guard routeLabel != nil else { return false }
        return event.chateau != NationalRailUtils.chateauID
            || isNationalRailRouteBadgeException
    }

    private var isNationalRailRouteBadgeException: Bool {
        guard event.chateau == NationalRailUtils.chateauID else { return false }

        let agencyID = routeInfo?.agencyId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if agencyID == "LO" || agencyID == "XR" {
            return true
        }

        let agencyName = NationalRailUtils.resolvedAgencyName(
            agencyID: routeInfo?.agencyId,
            agencyName: agency?.agencyName
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

        return agencyName == "london overground"
            || agencyName == "elizabeth line"
    }

    private var showsLeadingRoute: Bool {
        showsRouteBadge && (layout != .regular || mode != .rail)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if layout == .swiss {
                leadingRouteButton
            }

            StopDepartureTimeView(
                event: event,
                timezoneID: timezoneID,
                now: now,
                showCountdown: mode == .rail ? showCountdownsUnder1h : showLocalTransitCountdowns
            )

            if showsLeadingRoute, layout != .swiss {
                leadingRouteButton
            }

            Button(action: openTrip) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        destinationLabel
                            .foregroundStyle(event.isCancelled ? .red : .primary)
                            .strikethrough(event.isCancelled)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        metadataLine
                    }

                    Spacer(minLength: 4)

                    if let platformText {
                        Text(platformText)
                            .font(
                                mode == .rail
                                    ? .system(size: 14, weight: .regular)
                                    : .body.weight(.semibold)
                            )
                            .monospacedDigit()
                            .frame(minWidth: 24, alignment: .trailing)
                    }
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
    private var leadingRouteButton: some View {
        if showsRouteBadge {
            Button {
                openRoute()
            } label: {
                StopRouteBadge(
                    chateauID: event.chateau,
                    shortName: routeInfo?.shortName ?? event.tripShortName,
                    longName: routeInfo?.longName,
                    colorHex: routeInfo?.color,
                    textColorHex: routeInfo?.textColor,
                    mode: mode,
                    layout: layout
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open route")
        }
    }

    @ViewBuilder
    private var metadataLine: some View {
        let values = [
            mode == .rail ? nil : effectiveTripName,
            event.vehicleNumber
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        let hasAgency = mode == .rail && resolvedAgencyName != nil

        if layout == .regular, mode == .rail, showsRouteBadge || !values.isEmpty || hasAgency {
            HStack(spacing: 5) {
                if showsRouteBadge {
                    Button {
                        openRoute()
                    } label: {
                        StopRouteBadge(
                            chateauID: event.chateau,
                            shortName: routeInfo?.shortName ?? event.tripShortName,
                            longName: routeInfo?.longName,
                            colorHex: routeInfo?.color,
                            textColorHex: routeInfo?.textColor,
                            mode: mode,
                            layout: layout,
                            compact: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open route")
                }

                agencyMetadata

                if !values.isEmpty {
                    Text(values.joined(separator: "  •  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else if !values.isEmpty || hasAgency {
            HStack(spacing: 5) {
                agencyMetadata

                if !values.isEmpty {
                    Text(values.joined(separator: "  •  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var agencyMetadata: some View {
        if mode == .rail, let resolvedAgencyName {
            if event.chateau == NationalRailUtils.chateauID {
                NationalRailAgencyLabel(
                    agencyID: routeInfo?.agencyId,
                    agencyName: agency?.agencyName
                )
            } else {
                Text(resolvedAgencyName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var resolvedAgencyName: String? {
        if event.chateau == NationalRailUtils.chateauID {
            return NationalRailUtils.resolvedAgencyName(
                agencyID: routeInfo?.agencyId,
                agencyName: agency?.agencyName
            )
        }
        guard let value = agency?.agencyName.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private var destinationLabel: Text {
        var value = AttributedString(destinationText)
        value.font = mode == .rail
            ? .system(size: 14, weight: .medium)
            : .subheadline.weight(.semibold)

        if mode == .rail, let trainNumberText {
            var trainNumber = AttributedString(" \(trainNumberText)")
            trainNumber.font = .system(size: 14, weight: .regular)
            value.append(trainNumber)
        }

        return Text(value)
    }

    private var destinationComponents: [String] {
        var components: [String] = []

        for candidate in [event.finalStationName, event.headsign] {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  !components.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
                continue
            }
            components.append(value)
        }

        return components
    }

    private var destinationText: String {
        destinationComponents.isEmpty
            ? L10n.string("Departure")
            : destinationComponents.joined(separator: " ")
    }

    private var trainNumberText: String? {
        guard mode == .rail,
              let tripName = effectiveTripName,
              !destinationComponents.contains(where: {
                  $0.caseInsensitiveCompare(tripName) == .orderedSame
              }) else {
            return nil
        }
        return tripName
    }

    private var effectiveTripName: String? {
        let value = trainDisplayName ?? event.tripShortName
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private var routeLabel: String? {
        for value in [routeInfo?.shortName, routeInfo?.longName, event.tripShortName] {
            if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private var platformText: String? {
        guard let raw = event.platformStringRealtime?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let value = raw
            .replacingOccurrences(of: "Track", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Platform", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? raw : value
    }

    private func openRoute() {
        viewObject.push(.route(chateauID: event.chateau, routeID: event.routeId))
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
    let showCountdown: Bool

    @AppStorage("showSeconds") private var showSeconds = false

    private var scheduledTime: Int64? { event.scheduledTime }
    private var realtimeTime: Int64? { event.realtimeTime }

    private var resolvedTimezoneID: String {
        guard let timezoneID, TimeZone(identifier: timezoneID) != nil else {
            return TimeZone.autoupdatingCurrent.identifier
        }
        return timezoneID
    }

    private var isPast: Bool {
        (realtimeTime ?? scheduledTime ?? 0) < Int64(now.timeIntervalSince1970) - 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if event.tripCancelled == true {
                Text("Cancelled")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.red)
                if let scheduledTime {
                    clock(
                        scheduledTime,
                        size: 13,
                        weight: .regular,
                        color: Color.secondary.opacity(0.7)
                    )
                }
            } else if event.tripDeleted == true {
                Text("Deleted")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            } else if event.stopCancelled == true {
                Text("Stop cancelled")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            } else {
                if let realtimeTime,
                   let scheduledTime,
                   realtimeTime != scheduledTime {
                    clock(
                        scheduledTime,
                        size: 14,
                        weight: .regular,
                        color: Color.secondary.opacity(0.7)
                    )
                    clock(
                        realtimeTime,
                        size: 14,
                        weight: .medium,
                        color: Color.accentColor.opacity(isPast ? 0.7 : 1)
                    )
                    DelayDiff(
                        diff: realtimeTime - scheduledTime,
                        showSeconds: showSeconds,
                        fontSizeOfPolarity: 12,
                        useSymbolSign: false,
                        hideMinUnits: !showSeconds
                    )
                } else if let realtimeTime {
                    clock(
                        realtimeTime,
                        size: 14,
                        weight: .medium,
                        color: Color.accentColor.opacity(isPast ? 0.7 : 1)
                    )
                } else if let scheduledTime {
                    clock(
                        scheduledTime,
                        size: 14,
                        weight: .medium,
                        color: Color.primary.opacity(isPast ? 0.7 : 1)
                    )
                } else {
                    Text("—")
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if showCountdown,
                   let target = realtimeTime ?? scheduledTime,
                   target - Int64(now.timeIntervalSince1970) < 3_600 {
                    SelfUpdatingDiffTimer(
                        targetTimeSeconds: target,
                        showBrackets: false,
                        showSeconds: showSeconds,
                        showDays: false,
                        showPlus: false,
                        numSize: 13
                    )
                }
            }
        }
        .frame(width: showSeconds ? 70 : 62, alignment: .leading)
    }

    private func clock(
        _ time: Int64,
        size: CGFloat,
        weight: Font.Weight,
        color: Color
    ) -> some View {
        let font = Font.system(size: size, weight: weight).monospacedDigit()
        return FormattedTimeText(
            timezone: resolvedTimezoneID,
            timeSeconds: time,
            showSeconds: showSeconds,
            color: color,
            font: font,
            secondsFont: font
        )
    }
}

private struct StopRouteBadge: View {
    let chateauID: String
    let shortName: String?
    let longName: String?
    let colorHex: String?
    let textColorHex: String?
    let mode: StopTransitMode
    let layout: StopDepartureLayout
    var compact = false

    @ViewBuilder
    var body: some View {
        if let mtaRouteID {
            MTASubwayIcon(routeID: mtaRouteID, size: compact ? 16 : 20)
                .frame(
                    width: compact ? nil : (layout == .swiss ? 50 : 40),
                    alignment: layout == .swiss ? .leading : .center
                )
        } else {
            Text(label)
                .font(.system(size: layout == .swiss ? 12 : 10, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(StopHexColor.color(textColorHex, fallback: .white))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    StopHexColor.color(colorHex, fallback: fallbackColor),
                    in: routeShape
                )
                .frame(
                    width: compact ? nil : (layout == .swiss ? 50 : 40),
                    alignment: layout == .swiss ? .leading : .center
                )
        }
    }

    private var mtaRouteID: String? {
        guard chateauID == MTASubwayUtils.chateauID,
              let shortName,
              MTASubwayUtils.isSubwayRouteID(shortName) else {
            return nil
        }
        return shortName
    }

    private var label: String {
        if let shortName, !shortName.isEmpty { return shortName.replacingOccurrences(of: " Line", with: "") }
        if let longName, !longName.isEmpty { return String(longName.replacingOccurrences(of: " Line", with: "").prefix(8)) }
        return mode == .rail ? L10n.string("Rail") : "—"
    }

    private var routeShape: AnyShape {
        let isSBahn = (chateauID == "vbb" || chateauID == "deutschland")
            && label.range(of: #"^S\d+"#, options: .regularExpression) != nil
        if isSBahn {
            return AnyShape(Capsule())
        }
        return AnyShape(RoundedRectangle(cornerRadius: compact ? 3 : 4, style: .continuous))
    }

    private var fallbackColor: Color {
        if chateauID == "schweiz",
           label.hasPrefix("IR") || label.hasPrefix("IC") || label == "EC" {
            return Color(red: 0.92, green: 0, blue: 0)
        }

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
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
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
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
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

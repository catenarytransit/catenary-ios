import SwiftUI

struct StationTrainDepartureRow: View {
    let event: StopEvent
    let routeInfo: StopRouteInfo?
    let agency: StopAgencyInfo?
    let timezoneID: String?
    let now: Date
    var layout: StopDepartureLayout = .regular
    var trainDisplayName: String?

    var body: some View {
        StationDepartureRow(
            event: event,
            routeInfo: routeInfo,
            agency: agency,
            timezoneID: timezoneID,
            now: now,
            layout: layout,
            trainDisplayName: trainDisplayName
        )
    }
}

struct StationTrainDepartureRowCompact: View {
    let event: StopEvent
    let routeInfo: StopRouteInfo?
    let agency: StopAgencyInfo?
    let timezoneID: String?
    let now: Date
    var layout: StopDepartureLayout = .regular
    var trainDisplayName: String?
    var showAgencyName = true

    @EnvironmentObject private var viewObject: viewObject
    @AppStorage("showCountdownsUnder1h") private var showCountdownsUnder1h = false

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            if layout == .swiss {
                routeButton
            }

            CompactTrainDepartureTimeView(
                event: event,
                timezoneID: timezoneID,
                now: now,
                showCountdown: showCountdownsUnder1h
            )

            if layout == .eurostyle {
                routeButton
            }

            Button(action: openTrip) {
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destinationText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(event.isCancelled ? .red : .primary)
                            .strikethrough(event.isCancelled)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        metadataLine
                    }

                    if let platformText {
                        Text(platformText)
                            .font(.system(size: 11, weight: .regular))
                            .monospacedDigit()
                            .frame(minWidth: 22, alignment: .trailing)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(event.tripId == nil && event.routeId.isEmpty)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var routeButton: some View {
        if showsRouteBadge {
            Button(action: openRoute) {
                CompactTrainRouteBadge(
                    chateauID: event.chateau,
                    shortName: routeInfo?.shortName ?? event.tripShortName,
                    longName: routeInfo?.longName,
                    colorHex: routeInfo?.color,
                    textColorHex: routeInfo?.textColor,
                    layout: layout
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open route")
        }
    }

    @ViewBuilder
    private var metadataLine: some View {
        HStack(spacing: 5) {
            if layout == .regular {
                routeButton
            }

            if showAgencyName, let resolvedAgencyName {
                if event.chateau == NationalRailUtils.chateauID {
                    NationalRailAgencyLabel(
                        agencyID: routeInfo?.agencyId,
                        agencyName: agency?.agencyName,
                        compact: true
                    )
                } else {
                    Text(resolvedAgencyName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let effectiveTrainName,
               effectiveTrainName.caseInsensitiveCompare(routeLabel ?? "") != .orderedSame {
                Text(effectiveTrainName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let vehicleNumber = nonBlank(event.vehicleNumber) {
                Text(vehicleNumber)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var destinationText: String {
        var components: [String] = []
        for candidate in [event.finalStationName, event.headsign] {
            guard let value = nonBlank(candidate),
                  !components.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
                continue
            }
            components.append(value)
        }
        return components.isEmpty ? L10n.string("Departure") : components.joined(separator: " ")
    }

    private var routeLabel: String? {
        nonBlank(routeInfo?.shortName)
            ?? nonBlank(routeInfo?.longName)
            ?? nonBlank(event.tripShortName)
    }

    private var effectiveTrainName: String? {
        nonBlank(trainDisplayName) ?? nonBlank(event.tripShortName)
    }

    private var resolvedAgencyName: String? {
        if event.chateau == NationalRailUtils.chateauID {
            return NationalRailUtils.resolvedAgencyName(
                agencyID: routeInfo?.agencyId,
                agencyName: agency?.agencyName
            )
        }
        return nonBlank(agency?.agencyName)
    }

    private var showsRouteBadge: Bool {
        routeLabel != nil && event.chateau != NationalRailUtils.chateauID
    }

    private var platformText: String? {
        guard let raw = nonBlank(event.platformStringRealtime) else { return nil }
        let value = raw
            .replacingOccurrences(of: "Track", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Platform", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? raw : value
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
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

private struct CompactTrainDepartureTimeView: View {
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
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)
                if let scheduledTime {
                    clock(scheduledTime, weight: .regular, color: Color.secondary.opacity(0.7))
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
                    clock(scheduledTime, weight: .regular, color: Color.secondary.opacity(0.7))
                    clock(
                        realtimeTime,
                        weight: .medium,
                        color: Color.accentColor.opacity(isPast ? 0.7 : 1)
                    )
                    DelayDiff(
                        diff: realtimeTime - scheduledTime,
                        showSeconds: showSeconds,
                        fontSizeOfPolarity: 11,
                        valueFontSize: 11,
                        unitFontSize: 11,
                        useSymbolSign: true,
                        hideMinUnits: !showSeconds
                    )
                } else if let realtimeTime {
                    clock(
                        realtimeTime,
                        weight: .medium,
                        color: Color.accentColor.opacity(isPast ? 0.7 : 1)
                    )
                } else if let scheduledTime {
                    clock(
                        scheduledTime,
                        weight: .medium,
                        color: Color.primary.opacity(isPast ? 0.7 : 1)
                    )
                } else {
                    Text("—")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if showCountdown,
                   let target = realtimeTime ?? scheduledTime,
                   target - Int64(now.timeIntervalSince1970) > -60,
                   target - Int64(now.timeIntervalSince1970) < 3_600 {
                    SelfUpdatingDiffTimer(
                        targetTimeSeconds: target,
                        showBrackets: false,
                        showSeconds: showSeconds,
                        showDays: false,
                        showPlus: false,
                        numSize: 11,
                        unitSize: 9
                    )
                }
            }
        }
        .frame(width: showSeconds ? 76 : 58, alignment: .leading)
    }

    private func clock(
        _ time: Int64,
        weight: Font.Weight,
        color: Color
    ) -> some View {
        let font = Font.system(size: 11, weight: weight).monospacedDigit()
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

private struct CompactTrainRouteBadge: View {
    let chateauID: String
    let shortName: String?
    let longName: String?
    let colorHex: String?
    let textColorHex: String?
    let layout: StopDepartureLayout

    @ViewBuilder
    var body: some View {
        if let mtaRouteID {
            MTASubwayIcon(routeID: mtaRouteID, size: 18)
                .frame(width: layout == .swiss ? 50 : 40, alignment: .leading)
        } else if isSBahn {
            badgeLabel
                .background(backgroundColor, in: Capsule())
                .frame(width: layout == .swiss ? 50 : 40, alignment: .leading)
        } else {
            badgeLabel
                .background(
                    backgroundColor,
                    in: RoundedRectangle(cornerRadius: 3, style: .continuous)
                )
                .frame(width: layout == .swiss ? 50 : 40, alignment: .leading)
        }
    }

    private var badgeLabel: some View {
        Text(label)
            .font(.system(size: layout == .swiss ? 12 : 10, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(Color.transitHex(textColorHex, fallback: .white))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
    }

    private var label: String {
        if let shortName = nonBlank(shortName) {
            return shortName.replacingOccurrences(of: " Line", with: "")
        }
        if let longName = nonBlank(longName) {
            return String(longName.replacingOccurrences(of: " Line", with: "").prefix(8))
        }
        return L10n.string("Rail")
    }

    private var mtaRouteID: String? {
        guard chateauID == MTASubwayUtils.chateauID,
              let shortName = nonBlank(shortName),
              MTASubwayUtils.isSubwayRouteID(shortName) else {
            return nil
        }
        return shortName
    }

    private var isSBahn: Bool {
        (chateauID == "vbb" || chateauID == "deutschland")
            && label.range(of: #"^S\d+"#, options: .regularExpression) != nil
    }

    private var backgroundColor: Color {
        if chateauID == "schweiz",
           label.hasPrefix("IR") || label.hasPrefix("IC") || label == "EC" {
            return Color(red: 0.92, green: 0, blue: 0)
        }
        return Color.transitHex(colorHex, fallback: .railCategory)
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

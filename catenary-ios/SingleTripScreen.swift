import SwiftUI

@MainActor
struct SingleTripScreen: View {
    let selection: SingleTripSelection

    @EnvironmentObject private var viewObject: viewObject
    @StateObject private var model: SingleTripViewModel
    @AppStorage("singleTripShowOriginalTimetable") private var showOriginalTimetable = false
    @AppStorage("singleTripShowCountdown") private var showCountdown = true
    @State private var hasScrolledToCurrentStop = false
    @State private var showAlertsScreen = false

    init(selection: SingleTripSelection) {
        self.selection = selection
        _model = StateObject(wrappedValue: SingleTripViewModel(selection: selection))
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if model.isLoading {
                    loadingView
                } else if let errorMessage = model.errorMessage, model.tripData == nil {
                    errorView(errorMessage)
                } else if let tripData = model.tripData {
                    tripContent(tripData, proxy: proxy)
                } else {
                    CatenaryUnavailableView(
                        "Trip unavailable",
                        systemImage: "tram.fill",
                        description: Text("Ramonda did not return information for this trip.")
                    )
                }
            }
            .task {
                model.start()
            }
            .onDisappear {
                model.stop()
            }
            .catenaryOnChange(of: model.currentAtStopIndex) { _, _ in
                scrollToCurrentStopIfNeeded(proxy)
            }
            .catenaryOnChange(of: model.lastInactiveStopIndex) { _, _ in
                scrollToCurrentStopIfNeeded(proxy)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading trip")
                .font(.headline)
            Text(connectionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        CatenaryUnavailableView {
            Label("Unable to load trip", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(message)
                .textSelection(.enabled)
        } actions: {
            Button("Retry") {
                model.retry()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func tripContent(
        _ data: SingleTripDataResponse,
        proxy: ScrollViewProxy
    ) -> some View {
        let activeAlerts = Dictionary(uniqueKeysWithValues: model.activeAlerts(at: model.currentDate))

        return ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    RouteHeading(
                        color: data.color ?? "#808080",
                        textColor: data.textColor ?? "#000000",
                        routeType: data.routeType,
                        agencyName: nil,
                        shortName: data.routeShortName,
                        longName: data.routeLongName,
                        tripShortName: data.tripShortName,
                        chateauID: selection.chateauID,
                        isCompact: false,
                        routeClickable: (data.routeID ?? selection.routeID) != nil,
                        headsign: data.tripHeadsign,
                        onRouteClick: {
                            guard let routeID = data.routeID ?? selection.routeID else { return }
                            viewObject.push(.route(chateauID: selection.chateauID, routeID: routeID))
                        }
                    )

                    if data.isCancelled == true {
                        statusBanner(
                            text: "Cancelled",
                            systemImage: "xmark.octagon.fill",
                            color: .red
                        )
                    }

                    if data.deleted == true {
                        statusBanner(
                            text: "This trip was removed from the feed",
                            systemImage: "trash.fill",
                            color: .red
                        )
                    }

                    tripMetadata(data)

                    if !activeAlerts.isEmpty {
                        ServiceAlertsLink(alerts: activeAlerts) {
                            showAlertsScreen = true
                        }
                    }

                    displayOptions

                    ForEach(Array(model.stopTimes.enumerated()), id: \.offset) { item in
                        let index = item.offset
                        let stop = item.element
                        SingleTripStopRow(
                            stop: stop,
                            index: index,
                            totalStops: model.stopTimes.count,
                            tripTimezone: data.timezone,
                            currentDate: model.currentDate,
                            isPast: index <= model.lastInactiveStopIndex,
                            isCurrent: index == model.currentAtStopIndex,
                            movingDotProgress: index == model.movingDotSegmentIndex
                                ? model.movingDotProgress
                                : nil,
                            showOriginalTimetable: showOriginalTimetable,
                            showCountdown: showCountdown,
                            onTap: {
                                viewObject.push(.stop(
                                    chateauID: selection.chateauID,
                                    stopID: stop.raw.stopID
                                ))
                            }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 84)
            }

            if currentStopTarget != nil {
                Button {
                    scrollToCurrentStop(proxy, animated: true)
                } label: {
                    Image(systemName: "location.fill")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .catenaryCircularButtonBorderShape()
                .padding()
                .accessibilityLabel("Scroll to current stop")
            }
        }
        .fullScreenCover(isPresented: $showAlertsScreen) {
            ServiceAlertsScreen(
                alerts: activeAlerts,
                defaultTimezone: data.timezone,
                chateauID: selection.chateauID
            )
        }
    }

    private func routeHeader(_ data: SingleTripDataResponse) -> some View {
        Button {
            guard let routeID = data.routeID ?? selection.routeID else { return }
            viewObject.push(.route(chateauID: selection.chateauID, routeID: routeID))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(routeBadgeText(data))
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color(catenaryHex: data.textColor) ?? .white)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 48, minHeight: 38)
                    .background(
                        Color(catenaryHex: data.color) ?? routeTypeColor(data.routeType),
                        in: .rect(cornerRadius: 9)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    if let longName = nonEmpty(data.routeLongName), longName != data.routeShortName {
                        Text(longName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }

                    if let headsign = nonEmpty(data.tripHeadsign) {
                        Label(headsign, systemImage: "arrow.right")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }

                    if let tripShortName = nonEmpty(data.tripShortName) {
                        Text(tripShortName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Label(connectionLabel, systemImage: connectionSystemImage)
                        .font(.caption2)
                        .foregroundStyle(connectionColor)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(connectionLabel)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled((data.routeID ?? selection.routeID) == nil)
    }

    private func tripMetadata(_ data: SingleTripDataResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let vehicle = nonEmpty(data.vehicle?.label)
                    ?? nonEmpty(data.vehicle?.id)
                    ?? nonEmpty(selection.vehicleID) {
                    Button {
                        viewObject.push(
                            .vehicleHistory(
                                chateauID: selection.chateauID,
                                vehicleID: vehicle,
                                routeID: data.routeID ?? selection.routeID
                            )
                        )
                    } label: {
                        Label(vehicle, systemImage: "clock.arrow.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows previous trips operated by this vehicle")
                }

                if let blockID = nonEmpty(data.blockID),
                   let serviceDate = nonEmpty(data.serviceDate) {
                    Button {
                        viewObject.push(.block(
                            chateauID: selection.chateauID,
                            blockID: blockID,
                            serviceDate: serviceDate
                        ))
                    } label: {
                        Text(verbatim: L10n.format(
                            "trip.block",
                            defaultValue: "Block %@",
                            blockID
                        ))
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                Spacer()
            }

            if let occupancy = occupancyLabel {
                Label(occupancy, systemImage: "person.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var displayOptions: some View {
        Menu {
            Toggle("Show original timetable", isOn: $showOriginalTimetable)
            Toggle("Show countdowns", isOn: $showCountdown)
        } label: {
            Label("Trip display options", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func statusBanner(
        text: LocalizedStringKey,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(color.opacity(0.12), in: .rect(cornerRadius: 10))
    }

    private var currentStopTarget: Int? {
        let index: Int
        if model.currentAtStopIndex >= 0 {
            index = model.currentAtStopIndex
        } else {
            index = min(model.lastInactiveStopIndex + 1, model.stopTimes.count - 1)
        }
        guard model.stopTimes.indices.contains(index) else { return nil }
        return index
    }

    private func scrollToCurrentStopIfNeeded(_ proxy: ScrollViewProxy) {
        guard !hasScrolledToCurrentStop, currentStopTarget != nil else { return }
        hasScrolledToCurrentStop = true
        DispatchQueue.main.async {
            scrollToCurrentStop(proxy, animated: false)
        }
    }

    private func scrollToCurrentStop(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let target = currentStopTarget else { return }
        let action = { proxy.scrollTo(target, anchor: .center) }
        if animated {
            withAnimation(.easeInOut(duration: 0.25), action)
        } else {
            action()
        }
    }

    private func routeBadgeText(_ data: SingleTripDataResponse) -> String {
        nonEmpty(data.routeShortName)
            ?? nonEmpty(data.tripShortName)
            ?? nonEmpty(data.routeLongName)
            ?? L10n.string("Trip")
    }

    private var occupancyLabel: String? {
        if let percentage = model.vehicleData?.occupancyPercentage {
            return L10n.format(
                "occupancy.percentage",
                defaultValue: "Occupancy: %d%%",
                percentage
            )
        }

        guard let status = model.vehicleData?.occupancyStatus?.uppercased() else {
            return nil
        }
        let key: String
        switch status {
        case "EMPTY": key = "Empty"
        case "MANY_SEATS_AVAILABLE": key = "Many seats available"
        case "FEW_SEATS_AVAILABLE": key = "Few seats available"
        case "STANDING_ROOM_ONLY": key = "Standing room only"
        case "CRUSHED_STANDING_ROOM_ONLY": key = "Crushed standing room only"
        case "FULL": key = "Full"
        case "NOT_ACCEPTING_PASSENGERS": key = "Not accepting passengers"
        case "NO_DATA": key = "No data"
        case "NOT_BOARDABLE": key = "Not boardable"
        default: return nil
        }
        return L10n.string(key)
    }

    private var connectionLabel: String {
        switch model.connectionStatus {
        case "connected": return L10n.string("Live")
        case "connecting": return L10n.string("Connecting")
        case "error": return L10n.string("Reconnecting")
        default: return L10n.string("Offline")
        }
    }

    private var connectionSystemImage: String {
        switch model.connectionStatus {
        case "connected": return "antenna.radiowaves.left.and.right"
        case "connecting": return "arrow.trianglehead.2.clockwise.rotate.90"
        case "error": return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        default: return "wifi.slash"
        }
    }

    private var connectionColor: Color {
        switch model.connectionStatus {
        case "connected": return .green
        case "connecting": return .orange
        case "error": return .orange
        default: return .secondary
        }
    }

    private func routeTypeColor(_ routeType: Int?) -> Color {
        switch routeType {
        case 2, 100, 101, 102, 103, 106, 107:
            return .railCategory
        case 0, 1, 5, 7, 12, 900:
            return .metroCategory
        case 3, 11, 700:
            return .busCategory
        default:
            return .otherCategory
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

private struct SingleTripStopRow: View {
    let stop: SingleTripStopState
    let index: Int
    let totalStops: Int
    let tripTimezone: String?
    let currentDate: Date
    let isPast: Bool
    let isCurrent: Bool
    let movingDotProgress: Double?
    let showOriginalTimetable: Bool
    let showCountdown: Bool
    let onTap: () -> Void

    private let timeColumnWidth: CGFloat = 72
    private let timelineColumnWidth: CGFloat = 18
    private let columnSpacing: CGFloat = 8

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: columnSpacing) {
                VStack(alignment: .trailing, spacing: 1) {
                    if showOriginalTimetable,
                       let scheduledTimeText,
                       let realtimeTimeText,
                       scheduledTimeText != realtimeTimeText {
                        Text(scheduledTimeText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(realtimeTimeText ?? scheduledTimeText ?? "—")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(primaryTimeColor)

                    if let delaySeconds, abs(delaySeconds) >= 30 {
                        DelayDiff(
                            diff: delaySeconds,
                            showSeconds: false,
                            fontSizeOfPolarity: 10,
                            useSymbolSign: true,
                            hideMinUnits: true
                        )
                    }

                    if showCountdown, let countdown = countdownText {
                        Text(countdown)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: timeColumnWidth, alignment: .trailing)

                Color.clear
                    .frame(width: timelineColumnWidth)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(stop.displayName)
                            .font(.body.weight(isCurrent ? .bold : .regular))
                            .foregroundStyle(stop.isCancelled ? .secondary : .primary)
                            .strikethrough(stop.isCancelled)
                            .multilineTextAlignment(.leading)

                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }

                    if stop.raw.replacedStop == true {
                        Label("Replacement stop", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if stop.isCancelled {
                        Text("Stop cancelled")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    } else if isCurrent {
                        Text("At stop")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let platform = stop.platform {
                    Text(platform)
                        .font(.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 40, alignment: .trailing)
                        .accessibilityLabel("Platform \(platform)")
                } else {
                    Spacer()
                        .frame(width: 40)
                }
            }
            .frame(minHeight: 58, alignment: .top)
            .overlay(alignment: .topLeading) {
                SingleTripTimelineMarker(
                    isFirst: index == 0,
                    isLast: index == totalStops - 1,
                    isPast: isPast,
                    isCurrent: isCurrent,
                    movingProgress: movingDotProgress,
                    isCancelled: stop.isCancelled
                )
                .frame(width: timelineColumnWidth)
                .frame(maxHeight: .infinity)
                .offset(x: timeColumnWidth + columnSpacing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var realtimeEpochSeconds: Int64? {
        stop.realtimeDepartureTime ?? stop.realtimeArrivalTime
    }

    private var effectiveEpochSeconds: Int64? {
        realtimeEpochSeconds
            ?? stop.raw.scheduledDepartureTimeUnixSeconds
            ?? stop.raw.scheduledArrivalTimeUnixSeconds
            ?? stop.raw.interpolatedStoptimeUnixSeconds
    }

    private var scheduledEpochSeconds: Int64? {
        stop.raw.scheduledDepartureTimeUnixSeconds
            ?? stop.raw.scheduledArrivalTimeUnixSeconds
            ?? stop.raw.interpolatedStoptimeUnixSeconds
    }

    private var realtimeTimeText: String? {
        timeText(realtimeEpochSeconds)
    }

    private var scheduledTimeText: String? {
        timeText(scheduledEpochSeconds)
    }

    private var countdownText: String? {
        guard let effectiveEpochSeconds else { return nil }
        let difference = effectiveEpochSeconds - Int64(currentDate.timeIntervalSince1970)
        if difference <= -60 { return nil }
        if abs(difference) < 30 { return L10n.string("Now") }

        let minutes = Int(ceil(Double(abs(difference)) / 60))
        return L10n.format(
            "time.minutes",
            defaultValue: "%d min",
            difference > 0 ? minutes : -minutes
        )
    }

    private var delaySeconds: Int64? {
        stop.realtimeDepartureDifference ?? stop.realtimeArrivalDifference
    }

    private var delayText: String? {
        guard let delaySeconds, abs(delaySeconds) >= 30 else { return nil }
        let minutes = Int(round(Double(delaySeconds) / 60))
        return minutes > 0 ? "+\(minutes) min" : "\(minutes) min"
    }

    private var delayColor: Color {
        guard let delaySeconds else { return .secondary }
        if delaySeconds >= 300 { return .red }
        if delaySeconds >= 60 { return .orange }
        if delaySeconds <= -60 { return .blue }
        return .secondary
    }

    private var primaryTimeColor: Color {
        if stop.isCancelled { return .secondary }
        if isCurrent { return .green }
        return isPast ? .secondary : .primary
    }

    private func timeText(_ epochSeconds: Int64?) -> String? {
        guard let epochSeconds else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: stop.raw.timezone ?? tripTimezone ?? "")
            ?? .autoupdatingCurrent
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }
}

private struct SingleTripTimelineMarker: View {
    let isFirst: Bool
    let isLast: Bool
    let isPast: Bool
    let isCurrent: Bool
    let movingProgress: Double?
    let isCancelled: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY: CGFloat = 12
            let interRowSpacing: CGFloat = 12
            let lineWidth: CGFloat = isPast ? 1 : 2
            let dotDiameter: CGFloat = isCurrent ? 14 : 10
            let neutralColor: Color = colorScheme == .dark ? .white : .black
            let lineColor = neutralColor.opacity(isPast ? 0.5 : 1)

            ZStack(alignment: .topLeading) {
                if !isFirst {
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: lineWidth, height: centerY)
                        .offset(x: centerX - lineWidth / 2)
                }

                if !isLast {
                    Rectangle()
                        .fill(lineColor)
                        .frame(
                            width: lineWidth,
                            height: max(geometry.size.height - centerY + interRowSpacing, 0)
                        )
                        .offset(x: centerX - lineWidth / 2, y: centerY)

                    if let movingProgress {
                        let progress = CGFloat(max(0, min(1, movingProgress)))
                        let movingDotDiameter: CGFloat = 8
                        let availableHeight = max(
                            geometry.size.height - centerY + interRowSpacing - movingDotDiameter,
                            0
                        )

                        Circle()
                            .fill(neutralColor)
                            .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
                            .frame(width: movingDotDiameter, height: movingDotDiameter)
                            .offset(
                                x: centerX - movingDotDiameter / 2,
                                y: centerY + availableHeight * progress
                            )
                    }
                }

                Circle()
                    .fill(isCurrent ? Color.green : Color(uiColor: .systemBackground))
                    .overlay {
                        Circle()
                            .stroke(isCancelled ? Color.red : lineColor, lineWidth: 2)
                    }
                    .frame(width: dotDiameter, height: dotDiameter)
                    .offset(
                        x: centerX - dotDiameter / 2,
                        y: centerY - dotDiameter / 2
                    )
            }
        }
    }
}

private extension Color {
    init?(catenaryHex value: String?) {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard normalized.count == 6, let rgb = UInt64(normalized, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}


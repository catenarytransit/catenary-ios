import SwiftUI

@MainActor
struct SingleTripScreen: View {
    let selection: SingleTripSelection

    @EnvironmentObject private var viewObject: viewObject
    @StateObject private var model: SingleTripViewModel
    @AppStorage("singleTripShowPreviousStops") private var showPreviousStops = false
    @AppStorage("singleTripShowOriginalTimetable") private var showOriginalTimetable = false
    @AppStorage("singleTripShowCountdown") private var showCountdown = true
    @State private var alertsPresented = false
    @State private var hasScrolledToCurrentStop = false

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
                    ContentUnavailableView(
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
            .onChange(of: model.currentAtStopIndex) { _, _ in
                scrollToCurrentStopIfNeeded(proxy)
            }
            .onChange(of: model.lastInactiveStopIndex) { _, _ in
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
        ContentUnavailableView {
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
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    routeHeader(data)

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

                    let activeAlerts = model.activeAlerts(at: model.currentDate)
                    if !activeAlerts.isEmpty {
                        Button {
                            alertsPresented = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(alertTitle(activeAlerts))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Spacer()
                                Text("\(activeAlerts.count)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .foregroundStyle(.white)
                                    .background(.orange, in: .capsule)
                                Image(systemName: "chevron.forward")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $alertsPresented) {
                            NavigationStack {
                                SingleTripAlertsView(
                                    alerts: activeAlerts,
                                    timezone: data.timezone
                                )
                                .navigationTitle("Service alerts")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { alertsPresented = false }
                                    }
                                }
                            }
                        }
                    }

                    displayOptions

                    if !showPreviousStops, model.lastInactiveStopIndex > 0 {
                        Button {
                            withAnimation {
                                showPreviousStops = true
                            }
                        } label: {
                            Label(
                                "Show \(model.lastInactiveStopIndex) previous stops",
                                systemImage: "chevron.up"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    ForEach(visibleStops, id: \.offset) { item in
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
                .buttonBorderShape(.circle)
                .padding()
                .accessibilityLabel("Scroll to current stop")
            }
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
                    Label(vehicle, systemImage: "bus.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        Text("Block \(blockID)")
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
            Toggle("Show previous stops", isOn: $showPreviousStops)
            Toggle("Show original timetable", isOn: $showOriginalTimetable)
            Toggle("Show countdowns", isOn: $showCountdown)
        } label: {
            Label("Trip display options", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func statusBanner(text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(color.opacity(0.12), in: .rect(cornerRadius: 10))
    }

    private var visibleStops: [(offset: Int, element: SingleTripStopState)] {
        let enumerated = Array(model.stopTimes.enumerated())
        guard !showPreviousStops, model.lastInactiveStopIndex > 0 else { return enumerated }
        let firstVisible = max(model.lastInactiveStopIndex - 1, 0)
        return Array(enumerated.dropFirst(firstVisible))
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
            ?? "Trip"
    }

    private func alertTitle(_ alerts: [(String, SingleTripAlert)]) -> String {
        guard let text = alerts.first?.1.headerText?.preferredTranslation()?.text else {
            return "Service alerts"
        }
        return nonEmpty(plainText(text)) ?? "Service alerts"
    }

    private var occupancyLabel: String? {
        if let percentage = model.vehicleData?.occupancyPercentage {
            return "Occupancy: \(percentage)%"
        }
        return model.vehicleData?.occupancyStatus?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var connectionLabel: String {
        switch model.connectionStatus {
        case "connected": return "Live"
        case "connecting": return "Connecting"
        case "error": return "Reconnecting"
        default: return "Offline"
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

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    if showCountdown, let countdown = countdownText {
                        Text(countdown)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(primaryTimeColor)
                    } else {
                        Text(effectiveTimeText)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(primaryTimeColor)
                    }

                    if showOriginalTimetable,
                       let scheduledTimeText,
                       scheduledTimeText != effectiveTimeText {
                        Text(scheduledTimeText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .strikethrough(true)
                    }

                    if let delayText {
                        Text(delayText)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(delayColor)
                    }
                }
                .frame(width: 66, alignment: .trailing)

                SingleTripTimelineMarker(
                    isFirst: index == 0,
                    isLast: index == totalStops - 1,
                    isPast: isPast,
                    isCurrent: isCurrent,
                    movingProgress: movingDotProgress,
                    isCancelled: stop.isCancelled
                )
                .frame(width: 24, height: 66)

                VStack(alignment: .leading, spacing: 4) {
                    Text(stop.displayName)
                        .font(.body.weight(isCurrent ? .bold : .regular))
                        .foregroundStyle(stop.isCancelled ? .secondary : .primary)
                        .strikethrough(stop.isCancelled)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        if let platform = stop.platform {
                            Label(platform, systemImage: "rectangle.inset.filled")
                        }
                        if stop.raw.replacedStop == true {
                            Label("Replacement stop", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var effectiveEpochSeconds: Int64? {
        stop.realtimeDepartureTime
            ?? stop.realtimeArrivalTime
            ?? stop.raw.scheduledDepartureTimeUnixSeconds
            ?? stop.raw.scheduledArrivalTimeUnixSeconds
            ?? stop.raw.interpolatedStoptimeUnixSeconds
    }

    private var scheduledEpochSeconds: Int64? {
        stop.raw.scheduledDepartureTimeUnixSeconds
            ?? stop.raw.scheduledArrivalTimeUnixSeconds
            ?? stop.raw.interpolatedStoptimeUnixSeconds
    }

    private var effectiveTimeText: String {
        timeText(effectiveEpochSeconds) ?? "—"
    }

    private var scheduledTimeText: String? {
        timeText(scheduledEpochSeconds)
    }

    private var countdownText: String? {
        guard let effectiveEpochSeconds else { return nil }
        let difference = effectiveEpochSeconds - Int64(currentDate.timeIntervalSince1970)
        if difference <= -60 { return effectiveTimeText }
        if abs(difference) < 30 { return "Now" }

        let minutes = Int(ceil(Double(abs(difference)) / 60))
        return difference > 0 ? "\(minutes) min" : "-\(minutes) min"
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
        formatter.locale = .autoupdatingCurrent
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

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY: CGFloat = 14
            let lineColor: Color = isPast ? .secondary : .accentColor

            ZStack(alignment: .topLeading) {
                if !isFirst {
                    Rectangle()
                        .fill(lineColor.opacity(0.55))
                        .frame(width: 3, height: centerY)
                        .offset(x: centerX - 1.5)
                }

                if !isLast {
                    Rectangle()
                        .fill(lineColor.opacity(0.55))
                        .frame(width: 3, height: max(geometry.size.height - centerY, 0))
                        .offset(x: centerX - 1.5, y: centerY)

                    if let movingProgress {
                        let progress = CGFloat(movingProgress)
                        let availableHeight = max(geometry.size.height - centerY - 11, 0)

                        Circle()
                            .fill(.primary)
                            .overlay(Circle().stroke(.background, lineWidth: 2))
                            .frame(width: 11, height: 11)
                            .offset(
                                x: centerX - 5.5,
                                y: centerY + availableHeight * progress
                            )
                    }
                }

                Circle()
                    .fill(isCurrent ? Color.green : (isPast ? Color.secondary : Color(.systemBackground)))
                    .overlay {
                        Circle()
                            .stroke(isCancelled ? Color.red : lineColor, lineWidth: 3)
                    }
                    .frame(width: isCurrent ? 17 : 13, height: isCurrent ? 17 : 13)
                    .offset(
                        x: centerX - (isCurrent ? 8.5 : 6.5),
                        y: centerY - (isCurrent ? 8.5 : 6.5)
                    )
            }
        }
    }
}

private struct SingleTripAlertsView: View {
    let alerts: [(String, SingleTripAlert)]
    let timezone: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(alerts, id: \.0) { alertItem in
                    SingleTripAlertCard(
                        alert: alertItem.1,
                        timezone: timezone
                    )
                }
            }
            .padding()
        }
    }
}

private struct SingleTripAlertCard: View {
    let alert: SingleTripAlert
    let timezone: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(alertTitle)
                .font(.headline)

            if let alertDescription {
                Text(alertDescription)
                    .font(.body)
                    .textSelection(.enabled)
            }

            if let activePeriodText {
                Label(activePeriodText, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let moreInformationURL {
                Link("More information", destination: moreInformationURL)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 14))
    }

    private var alertTitle: String {
        guard let text = alert.headerText?.preferredTranslation()?.text else {
            return "Service alert"
        }
        return plainText(text)
    }

    private var alertDescription: String? {
        guard let text = alert.descriptionText?.preferredTranslation()?.text else {
            return nil
        }
        let description = plainText(text)
        return description.isEmpty ? nil : description
    }

    private var moreInformationURL: URL? {
        guard let text = alert.url?.preferredTranslation()?.text else {
            return nil
        }
        return URL(string: plainText(text))
    }

    private var activePeriodText: String? {
        guard let period = alert.activePeriod.first,
              period.start != nil || period.end != nil else { return nil }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: timezone ?? "") ?? .autoupdatingCurrent

        let start = period.start.map {
            formatter.string(from: Date(timeIntervalSince1970: TimeInterval($0)))
        }
        let end = period.end.map {
            formatter.string(from: Date(timeIntervalSince1970: TimeInterval($0)))
        }

        switch (start, end) {
        case let (.some(start), .some(end)):
            return "\(start) – \(end)"
        case let (.some(start), .none):
            return "From \(start)"
        case let (.none, .some(end)):
            return "Until \(end)"
        case (.none, .none):
            return nil
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

private func plainText(_ html: String) -> String {
    html
        .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

import Combine
import CoreLocation
import Foundation
import SwiftUI

private struct StopAPIResponse: Decodable {
    let primary: StopAPIPrimary?
    let routes: [String: [String: StopAPIRouteInfo]]?
    let events: [StopAPIEvent]?
    let stops: [StopAPIPrimary]?
}

private struct StopAPIPrimary: Decodable, Equatable {
    let stopName: String
    let stopLon: Double
    let stopLat: Double
    let timezone: String
}

private struct StopAPIRouteInfo: Decodable {
    let color: String?
    let textColor: String?
    let shortName: String?
    let longName: String?
    let routeType: Int?
    let agencyId: String?
}

private struct StopAPIEvent: Decodable, Identifiable {
    let chateau: String
    let tripId: String?
    let routeId: String
    let serviceDate: String?
    let headsign: String?
    let stopId: String
    let scheduledDeparture: Int64?
    let realtimeDeparture: Int64?
    let scheduledArrival: Int64?
    let realtimeArrival: Int64?
    let tripShortName: String?
    let lastStop: Bool?
    let platformStringRealtime: String?
    let vehicleNumber: String?
    let delaySeconds: Int64?
    let tripCancelled: Bool?
    let stopCancelled: Bool?
    let tripDeleted: Bool?
    let routeType: Int?
    let timezone: String?
    let distanceM: Double?
    let finalStationName: String?

    var id: String {
        "event|\(chateau)|\(tripId ?? "")|\(routeId)|\(stopId)|\(serviceDate ?? "")|\(scheduledDeparture ?? scheduledArrival ?? 0)"
    }

    var effectiveTime: Int64? {
        realtimeTime ?? scheduledTime
    }

    var scheduledTime: Int64? {
        if lastStop == true {
            return scheduledArrival
        }
        return scheduledDeparture
    }

    var realtimeTime: Int64? {
        if lastStop == true {
            return realtimeArrival
        }
        return realtimeDeparture
    }

    var isCancelled: Bool {
        tripCancelled == true || stopCancelled == true || tripDeleted == true
    }

    var isTerminalArrivalOnly: Bool {
        lastStop == true && scheduledDeparture == nil && realtimeDeparture == nil
    }
}

private struct StopRedirectResponse: Decodable {
    let redirectToOsmStationId: Int64
}

private struct StopDayGroup: Identifiable {
    let day: String
    let events: [StopAPIEvent]

    var id: String { day }
}

private struct StopStationLookupResponse: Decodable {
    let found: Bool
    let osmStationId: Int64?
    let osmStationInfo: StopStationLookupInfo?
}

private struct StopStationLookupInfo: Decodable {
    let name: String?
    let modeType: String?
    let lat: Double?
    let lon: Double?
}

@MainActor
private final class StopScreenViewModel: ObservableObject {
    @Published var primary: StopAPIPrimary?
    @Published var routes: [String: [String: StopAPIRouteInfo]] = [:]
    @Published var events: [StopAPIEvent] = []
    @Published var isLoading = false
    @Published var isLoadingEarlier = false
    @Published var isLoadingLater = false
    @Published var errorMessage: String?
    @Published var redirectToOSMStationID: Int64?

    private var source: StopScreenSource?
    private var windowStart: Int64 = 0
    private var windowEnd: Int64 = 0
    private var eventIndex: [String: StopAPIEvent] = [:]

    var timezoneID: String? {
        primary?.timezone ?? events.compactMap(\.timezone).first
    }

    func reset(source: StopScreenSource, anchor: Date) async {
        self.source = source
        eventIndex.removeAll(keepingCapacity: true)
        events = []
        routes = [:]
        primary = nil
        errorMessage = nil
        redirectToOSMStationID = nil

        let anchorSeconds = Int64(anchor.timeIntervalSince1970)
        windowStart = anchorSeconds - 10 * 60
        windowEnd = anchorSeconds + 2 * 60 * 60
        isLoading = true
        await fetch(start: windowStart, end: windowEnd)
        isLoading = false
    }

    func refresh() async {
        guard source != nil else { return }
        await fetch(start: windowStart, end: windowEnd)
    }

    func loadEarlier() async {
        guard source != nil, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        let newStart = windowStart - 60 * 60
        await fetch(start: newStart, end: windowStart + 5 * 60)
        windowStart = newStart
        isLoadingEarlier = false
    }

    func loadLater() async {
        guard source != nil, !isLoadingLater else { return }
        isLoadingLater = true
        let newEnd = windowEnd + 2 * 60 * 60
        await fetch(start: windowEnd - 5 * 60, end: newEnd)
        windowEnd = newEnd
        isLoadingLater = false
    }

    private func fetch(start: Int64, end: Int64) async {
        guard let source, let url = makeURL(source: source, start: start, end: end) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let redirect = try? decoder.decode(StopRedirectResponse.self, from: data) {
                redirectToOSMStationID = redirect.redirectToOsmStationId
                return
            }
            let payload = try decoder.decode(StopAPIResponse.self, from: data)
            merge(payload)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if events.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func makeURL(source: StopScreenSource, start: Int64, end: Int64) -> URL? {
        var components: URLComponents
        switch source {
        case let .stop(chateauID, stopID):
            components = URLComponents(string: "https://birchdeparturesfromstop.catenarymaps.org/departures_at_stop")!
            components.queryItems = [
                URLQueryItem(name: "chateau_id", value: chateauID),
                URLQueryItem(name: "stop_id", value: stopID),
                URLQueryItem(name: "greater_than_time", value: String(start)),
                URLQueryItem(name: "less_than_time", value: String(end)),
                URLQueryItem(name: "include_shapes", value: "false")
            ]
        case let .osmStation(id):
            components = URLComponents(string: "https://birch.catenarymaps.org/departures_at_osm_station")!
            components.queryItems = [
                URLQueryItem(name: "osm_station_id", value: id),
                URLQueryItem(name: "greater_than_time", value: String(start)),
                URLQueryItem(name: "less_than_time", value: String(end)),
                URLQueryItem(name: "include_shapes", value: "false")
            ]
        }
        return components.url
    }

    private func merge(_ payload: StopAPIResponse) {
        if let primary = payload.primary {
            self.primary = primary
        } else if self.primary == nil, let first = payload.stops?.first {
            self.primary = first
        }

        for (chateau, routeMap) in payload.routes ?? [:] {
            routes[chateau, default: [:]].merge(routeMap) { _, new in new }
        }

        for event in payload.events ?? [] {
            eventIndex[event.id] = event
        }
        events = eventIndex.values.sorted {
            ($0.effectiveTime ?? .max) < ($1.effectiveTime ?? .max)
        }
    }
}

struct StopScreenView: View {
    let destination: CatenaryStackItem

    @EnvironmentObject private var viewObject: viewObject
    @StateObject private var model = StopScreenViewModel()
    @State private var selectedDate: Date
    @State private var isNow: Bool
    @State private var selectedModes = Set(TransitDisplayMode.allCases)
    @State private var showEarlierDepartures = false
    @State private var checkedRedirectSource: String?
    @State private var centeredSource: String?

    init(destination: CatenaryStackItem) {
        self.destination = destination
        let epoch: Int64?
        switch destination {
        case let .stop(_, _, timeEpochSeconds):
            epoch = timeEpochSeconds
        case let .osmStation(_, _, _, _, _, timeEpochSeconds):
            epoch = timeEpochSeconds
        default:
            epoch = nil
        }
        _selectedDate = State(initialValue: epoch.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date())
        _isNow = State(initialValue: epoch == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            TransitTimePicker(
                selectedDate: $selectedDate,
                isNow: $isNow,
                timezoneID: timezoneID,
                onCommit: { date, now in
                    if now {
                        selectedDate = Date()
                        viewObject.updateCurrentStopTime(nil)
                    } else if let date {
                        selectedDate = date
                        viewObject.updateCurrentStopTime(Int64(date.timeIntervalSince1970))
                    }
                }
            )

            if availableModes.count > 1 {
                TransitModePicker(availableModes: availableModes, selectedModes: $selectedModes)
            }

            if model.isLoading {
                ProgressView().progressViewStyle(.linear)
            }

            if let error = model.errorMessage, model.events.isEmpty {
                ContentUnavailableView("Unable to load departures", systemImage: "wifi.exclamationmark", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                departuresList
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .task(id: source.id) {
            await redirectToOSMStationIfNeeded()
        }
        .task(id: loadKey) {
            let anchor = isNow ? Date() : selectedDate
            await model.reset(source: source, anchor: anchor)
            centerMapIfNeeded()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                await model.refresh()
                centerMapIfNeeded()
            }
        }
        .onChange(of: model.primary) { _, _ in
            centerMapIfNeeded()
        }
        .onChange(of: model.redirectToOSMStationID) { _, stationID in
            guard let stationID else { return }
            viewObject.replaceTop(with: .osmStation(
                osmStationID: String(stationID),
                stationName: nil,
                modeType: nil,
                latitude: nil,
                longitude: nil,
                timeEpochSeconds: isNow ? nil : Int64(selectedDate.timeIntervalSince1970)
            ))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                if let timezoneID {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(clockText(context.date, timezoneID: timezoneID))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(timezoneID)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
    }

    private var departuresList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Button {
                    showEarlierDepartures = true
                    Task { await model.loadEarlier() }
                } label: {
                    HStack {
                        Spacer()
                        if model.isLoadingEarlier { ProgressView() }
                        Label("Earlier departures", systemImage: "chevron.up")
                        Spacer()
                    }
                    .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 8)

                ForEach(groupedDays) { group in
                    Section {
                        ForEach(group.events) { event in
                            StopDepartureRow(
                                event: event,
                                routeInfo: model.routes[event.chateau]?[event.routeId],
                                timezoneID: event.timezone ?? timezoneID
                            )
                            Divider().padding(.leading, 48)
                        }
                    } header: {
                        Text(group.day)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                }

                if groupedDays.isEmpty && !model.isLoading {
                    ContentUnavailableView("No departures in this time range", systemImage: "clock.badge.xmark")
                        .padding(.vertical, 28)
                }

                Button {
                    Task { await model.loadLater() }
                } label: {
                    HStack {
                        Spacer()
                        if model.isLoadingLater { ProgressView() }
                        Label("Later departures", systemImage: "chevron.down")
                        Spacer()
                    }
                    .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)

                Color.clear.frame(height: 16)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
    }

    private var filteredEvents: [StopAPIEvent] {
        let cutoff = showEarlierDepartures
            ? Int64.min
            : Int64((isNow ? Date() : selectedDate).timeIntervalSince1970) - 60
        return model.events.filter { event in
            selectedModes.contains(TransitDisplayMode.from(routeType: event.routeType ?? model.routes[event.chateau]?[event.routeId]?.routeType))
                && !event.isTerminalArrivalOnly
                && (event.effectiveTime ?? 0) >= cutoff
        }
    }

    private var groupedDays: [StopDayGroup] {
        let groups = Dictionary(grouping: filteredEvents) { event in
            TransitFormatting.day(event.effectiveTime ?? 0, timezoneID: event.timezone ?? timezoneID)
        }
        return groups.map { key, value in
            StopDayGroup(
                day: key,
                events: value.sorted { ($0.effectiveTime ?? .max) < ($1.effectiveTime ?? .max) }
            )
        }
        .sorted { ($0.events.first?.effectiveTime ?? .max) < ($1.events.first?.effectiveTime ?? .max) }
    }

    private var availableModes: [TransitDisplayMode] {
        let set = Set(model.events.map { event in
            TransitDisplayMode.from(routeType: event.routeType ?? model.routes[event.chateau]?[event.routeId]?.routeType)
        })
        return TransitDisplayMode.allCases.filter(set.contains)
    }

    private var source: StopScreenSource {
        guard let source = StopScreenSource(destination: destination) else {
            preconditionFailure("StopScreenView received an unsupported destination")
        }
        return source
    }

    private var loadKey: String {
        let time = isNow ? "now" : String(Int64(selectedDate.timeIntervalSince1970 / 60) * 60)
        return "\(source.id)|\(time)"
    }

    private var title: String {
        if let name = model.primary?.stopName, !name.isEmpty { return name }
        if case let .osmStation(_, stationName, _, _, _, _) = destination,
           let stationName, !stationName.isEmpty {
            return stationName
        }
        return source.id.hasPrefix("osm|")
            ? L10n.string("Station")
            : L10n.string("Stop")
    }

    private var timezoneID: String? {
        model.timezoneID
    }

    private func clockText(_ date: Date, timezoneID: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.timeZone = TimeZone(identifier: timezoneID) ?? .autoupdatingCurrent
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func redirectToOSMStationIfNeeded() async {
        guard case let .stop(chateauID, stopID) = source,
              checkedRedirectSource != source.id else { return }
        checkedRedirectSource = source.id

        var components = URLComponents(string: "https://birch.catenarymaps.org/osm_station_lookup")!
        components.queryItems = [
            URLQueryItem(name: "chateau_id", value: chateauID),
            URLQueryItem(name: "gtfs_stop_id", value: stopID)
        ]
        guard let url = components.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let lookup = try decoder.decode(StopStationLookupResponse.self, from: data)
            guard lookup.found, let osmID = lookup.osmStationId else { return }
            viewObject.replaceTop(with: .osmStation(
                osmStationID: String(osmID),
                stationName: lookup.osmStationInfo?.name,
                modeType: lookup.osmStationInfo?.modeType,
                latitude: lookup.osmStationInfo?.lat,
                longitude: lookup.osmStationInfo?.lon,
                timeEpochSeconds: isNow ? nil : Int64(selectedDate.timeIntervalSince1970)
            ))
        } catch {
            // A lookup failure should not prevent the GTFS stop screen from loading.
        }
    }

    private func centerMapIfNeeded() {
        guard centeredSource != source.id else { return }
        let coordinate: CLLocationCoordinate2D?
        if let primary = model.primary {
            coordinate = CLLocationCoordinate2D(latitude: primary.stopLat, longitude: primary.stopLon)
        } else if case let .osmStation(_, _, _, latitude, longitude, _) = destination,
                  let latitude, let longitude {
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            coordinate = nil
        }
        guard let coordinate else { return }
        viewObject.camera = .center(coordinate, zoom: 14)
        centeredSource = source.id
    }
}

private struct StopDepartureRow: View {
    let event: StopAPIEvent
    let routeInfo: StopAPIRouteInfo?
    let timezoneID: String?

    @EnvironmentObject private var viewObject: viewObject

    var body: some View {
        HStack(spacing: 10) {
            Button {
                viewObject.push(.route(chateauID: event.chateau, routeID: event.routeId))
            } label: {
                TransitRouteBadge(
                    shortName: routeInfo?.shortName,
                    longName: routeInfo?.longName,
                    colorHex: routeInfo?.color,
                    textColorHex: routeInfo?.textColor
                )
                .frame(width: 42)
            }
            .buttonStyle(.plain)

            Button {
                viewObject.push(.singleTrip(
                    chateauID: event.chateau,
                    tripID: event.tripId,
                    routeID: event.routeId,
                    startTime: nil,
                    startDate: event.serviceDate,
                    vehicleID: event.vehicleNumber,
                    routeType: event.routeType ?? routeInfo?.routeType
                ))
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.finalStationName ?? event.headsign ?? L10n.string("Departure"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(event.isCancelled ? .red : .primary)
                            .strikethrough(event.isCancelled)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if let trip = event.tripShortName, !trip.isEmpty {
                                Text(trip)
                            }
                            if let platform = event.platformStringRealtime, !platform.isEmpty {
                                Text(verbatim: L10n.format(
                                    "platform.value",
                                    defaultValue: "Platform %@",
                                    platform
                                ))
                            }
                            if let vehicle = event.vehicleNumber, !vehicle.isEmpty {
                                Text(vehicle)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    StopDepartureTimeColumn(
                        event: event,
                        timezoneID: timezoneID
                    )
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

/// Mirrors the Android StopScreenRowV2 time column. Scheduled and realtime
/// clocks use the same 14-point size, while delay and countdown rendering are
/// delegated to the shared Android-port views instead of ad-hoc strings.
private struct StopDepartureTimeColumn: View {
    let event: StopAPIEvent
    let timezoneID: String?

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
        (realtimeTime ?? scheduledTime ?? 0) < Int64(Date().timeIntervalSince1970) - 60
    }

    private var statusText: LocalizedStringKey? {
        if event.tripCancelled == true { return "Cancelled" }
        if event.tripDeleted == true { return "Deleted" }
        if event.stopCancelled == true { return "Stop cancelled" }
        return nil
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let statusText {
                Text(statusText)
                    .font(.system(
                        size: event.tripCancelled == true ? 13 : 10,
                        weight: event.tripCancelled == true ? .bold : .regular
                    ))
                    .foregroundStyle(.red)

                if let scheduledTime {
                    clock(
                        scheduledTime,
                        size: 13,
                        weight: .regular,
                        color: Color.secondary.opacity(0.7)
                    )
                }
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

                if let target = realtimeTime ?? scheduledTime,
                   target - Int64(Date().timeIntervalSince1970) < 3_600 {
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
        .fixedSize(horizontal: true, vertical: false)
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

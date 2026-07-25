import Combine
import CoreLocation
import Foundation
import SwiftUI

private struct NearbyAPIResponse: Decodable {
    var longDistance: [NearbyStationGroup] = []
    var local: [NearbyRouteGroup] = []
    var routes: [String: [String: NearbyRouteInfo]] = [:]
    var stops: [String: [String: NearbyStopInfo]] = [:]
    var debug: NearbyDebugInfo? = nil
}

private struct NearbyDebugInfo: Decodable {
    let totalTimeMs: Int64?
}

private struct NearbyStationGroup: Decodable, Identifiable {
    let stationName: String
    let osmStationId: Int64?
    let distanceM: Double
    let departures: [NearbyStationDeparture]
    let lat: Double
    let lon: Double
    let timezone: String

    var id: String { "station|\(osmStationId.map(String.init) ?? stationName)|\(lat)|\(lon)" }
}

private struct NearbyStationDeparture: Decodable, Identifiable {
    let scheduledDeparture: Int64?
    let realtimeDeparture: Int64?
    let scheduledArrival: Int64?
    let realtimeArrival: Int64?
    let serviceDate: String?
    let headsign: String
    let platform: String?
    let tripId: String?
    let tripShortName: String?
    let routeId: String
    let stopId: String
    let cancelled: Bool?
    let delayed: Bool?
    let chateauId: String
    let lastStop: Bool?
    let finalStationName: String?

    var id: String {
        "station-departure|\(chateauId)|\(tripId ?? "")|\(routeId)|\(stopId)|\(scheduledDeparture ?? scheduledArrival ?? 0)"
    }

    var effectiveDeparture: Int64? {
        if let realtimeDeparture { return realtimeDeparture }
        if let scheduledDeparture,
           let realtimeArrival,
           realtimeArrival > scheduledDeparture {
            return realtimeArrival
        }
        return scheduledDeparture ?? scheduledArrival
    }
}

private struct NearbyRouteGroup: Decodable, Identifiable {
    let chateauId: String
    let routeId: String
    let color: String?
    let textColor: String?
    let shortName: String?
    let longName: String?
    let routeType: Int?
    let agencyName: String?
    let headsigns: [String: [NearbyLocalDeparture]]
    let closestDistance: Double

    var id: String { "route|\(chateauId)|\(routeId)" }
}

private struct NearbyLocalDeparture: Decodable, Identifiable {
    let tripId: String?
    let departureSchedule: Int64?
    let departureRealtime: Int64?
    let arrivalSchedule: Int64?
    let arrivalRealtime: Int64?
    let stopId: String
    let stopName: String?
    let cancelled: Bool?
    let platform: String?
    let lastStop: Bool?
    let serviceDate: String?

    var id: String {
        "local-departure|\(tripId ?? "")|\(stopId)|\(departureSchedule ?? arrivalSchedule ?? 0)"
    }

    var effectiveDeparture: Int64? {
        departureRealtime ?? arrivalRealtime ?? departureSchedule ?? arrivalSchedule
    }
}

private struct NearbyRouteInfo: Decodable {
    let shortName: String?
    let longName: String?
    let agencyName: String?
    let color: String?
    let textColor: String?
    let routeType: Int?
}

private struct NearbyStopInfo: Decodable {
    let gtfsId: String?
    let name: String
    let lat: Double
    let lon: Double
    let osmStationId: Int64?
    let timezone: String?
}

@MainActor
private final class NearbyDeparturesViewModel: ObservableObject {
    @Published var response = NearbyAPIResponse()
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var errorMessage: String?

    func load(origin: CLLocationCoordinate2D, departureTime: Int64?) async {
        var components = URLComponents(string: "https://birch.catenarymaps.org/nearbydeparturesfromcoordsv3")!
        var queryItems = [
            URLQueryItem(name: "lat", value: String(origin.latitude)),
            URLQueryItem(name: "lon", value: String(origin.longitude)),
            URLQueryItem(name: "limit_per_station", value: "10"),
            URLQueryItem(name: "limit_per_headsign", value: "20")
        ]
        if let departureTime {
            queryItems.append(URLQueryItem(name: "departure_time", value: String(departureTime)))
        }
        components.queryItems = queryItems
        guard let url = components.url else { return }

        isLoading = !hasLoaded
        errorMessage = nil
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            self.response = try decoder.decode(NearbyAPIResponse.self, from: data)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            if !hasLoaded {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}

private enum NearbySortMode: String, CaseIterable, Identifiable {
    case distance
    case alphabetic

    var id: String { rawValue }
    var label: String { self == .distance ? "Distance" : "Name" }
    var symbol: String { self == .distance ? "ruler" : "textformat.abc" }
}

private enum NearbyListItem: Identifiable {
    case station(NearbyStationGroup, [NearbyStationDeparture])
    case route(NearbyRouteGroup, [String: NearbyStopInfo])

    var id: String {
        switch self {
        case let .station(group, _): return group.id
        case let .route(group, _): return group.id
        }
    }

    var distance: Double {
        switch self {
        case let .station(group, _): return group.distanceM
        case let .route(group, _): return group.closestDistance
        }
    }

    var name: String {
        switch self {
        case let .station(group, _): return group.stationName
        case let .route(group, _): return group.shortName ?? group.longName ?? group.routeId
        }
    }
}

struct NearbyDeparturesView: View {
    @ObservedObject var locationManager: LocationManager
    let fixedOrigin: CLLocationCoordinate2D?
    @Binding private var pinActive: Bool
    @Binding private var pickedCoordinate: CLLocationCoordinate2D?

    @EnvironmentObject private var viewObject: viewObject
    @StateObject private var model = NearbyDeparturesViewModel()
    @State private var lockedOrigin: CLLocationCoordinate2D?
    @State private var selectedDate = Date()
    @State private var isNow = true
    @State private var sortMode: NearbySortMode = .distance
    @State private var selectedModes = Set(TransitDisplayMode.allCases)
    @State private var reloadNonce = 0

    init(
        locationManager: LocationManager,
        fixedOrigin: CLLocationCoordinate2D? = nil,
        pinActive: Binding<Bool> = .constant(false),
        pickedCoordinate: Binding<CLLocationCoordinate2D?> = .constant(nil)
    ) {
        self.locationManager = locationManager
        self.fixedOrigin = fixedOrigin
        _pinActive = pinActive
        _pickedCoordinate = pickedCoordinate
        _lockedOrigin = State(
            initialValue: fixedOrigin ?? (pinActive.wrappedValue ? pickedCoordinate.wrappedValue : nil)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if fixedOrigin == nil {
                controls
            } else {
                Label("Departures near selected location", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let origin = lockedOrigin {
                HStack(spacing: 8) {
                    TransitTimePicker(
                        selectedDate: $selectedDate,
                        isNow: $isNow,
                        timezoneID: nearbyTimezone,
                        onCommit: { date, now in
                            isNow = now
                            if let date { selectedDate = date }
                            reloadNonce += 1
                        }
                    )

                    if let serverMs = model.response.debug?.totalTimeMs {
                        Text("\(serverMs) ms")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }

                if availableModes.count > 1 {
                    TransitModePicker(availableModes: availableModes, selectedModes: $selectedModes)
                }

                if model.isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                }

                content(origin: origin)
            } else {
                ContentUnavailableView {
                    Label("Waiting for location", systemImage: "location.slash")
                } description: {
                    Text("Allow location access, or use the current map center to see nearby departures.")
                } actions: {
                    Button("Request location") {
                        locationManager.checkLocationAuthorization()
                    }
                    Button("Drop pin at map center") {
                        dropPinAtMapCenter()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .task {
            if fixedOrigin == nil {
                locationManager.checkLocationAuthorization()
                lockFirstLocationIfNeeded()
            }
        }
        .onChange(of: locationManager.lastKnownLocation?.latitude) { _, _ in
            lockFirstLocationIfNeeded()
        }
        .onChange(of: locationManager.lastKnownLocation?.longitude) { _, _ in
            lockFirstLocationIfNeeded()
        }
        .onChange(of: pinActive) { _, active in
            guard fixedOrigin == nil else { return }
            if active, let pickedCoordinate {
                lockedOrigin = pickedCoordinate
                reloadNonce += 1
            } else {
                lockedOrigin = locationManager.lastKnownLocation
                reloadNonce += 1
            }
        }
        .onChange(of: pickedCoordinate?.latitude) { _, _ in
            updateFromDraggedPin()
        }
        .onChange(of: pickedCoordinate?.longitude) { _, _ in
            updateFromDraggedPin()
        }
        .task(id: requestKey) {
            guard let origin = lockedOrigin else { return }
            let departureTime = isNow ? nil : Int64(selectedDate.timeIntervalSince1970)
            await model.load(origin: origin, departureTime: departureTime)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                await model.load(origin: origin, departureTime: departureTime)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                pinActive = false
                if let coordinate = locationManager.lastKnownLocation {
                    lockedOrigin = coordinate
                    isNow = true
                    selectedDate = Date()
                    reloadNonce += 1
                } else {
                    locationManager.checkLocationAuthorization()
                }
            } label: {
                Label("My location", systemImage: pinActive ? "location" : "location.fill")
            }
            .buttonStyle(.bordered)

            Button {
                dropPinAtMapCenter()
            } label: {
                Label(pinActive ? "Move pin" : "Drop pin", systemImage: "mappin.and.ellipse")
            }
            .buttonStyle(.bordered)

            if pinActive {
                Button {
                    centerPinOnMap()
                } label: {
                    Image(systemName: "scope")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Center pin on map")
            }

            Spacer()

            Menu {
                Picker("Sort", selection: $sortMode) {
                    ForEach(NearbySortMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
            } label: {
                Image(systemName: sortMode.symbol)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func content(origin: CLLocationCoordinate2D) -> some View {
        if let errorMessage = model.errorMessage, !model.hasLoaded {
            ContentUnavailableView("Unable to load departures", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if listItems.isEmpty && model.hasLoaded && !model.isLoading {
            ContentUnavailableView("No nearby departures", systemImage: "clock.badge.xmark")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(listItems) { item in
                        switch item {
                        case let .station(group, departures):
                            NearbyStationCard(group: group, departures: departures, routeMap: model.response.routes)
                        case let .route(group, stops):
                            NearbyRouteCard(group: group, stops: stops, timezoneID: nearbyTimezone)
                        }
                    }
                    Color.clear.frame(height: 12)
                }
            }
            .scrollIndicators(.hidden)
            .refreshable {
                let departureTime = isNow ? nil : Int64(selectedDate.timeIntervalSince1970)
                await model.load(origin: origin, departureTime: departureTime)
            }
        }
    }

    private var availableModes: [TransitDisplayMode] {
        let routeModes = model.response.local.map { TransitDisplayMode.from(routeType: $0.routeType) }
        let stationModes = model.response.longDistance.flatMap { group in
            group.departures.map { departure in
                TransitDisplayMode.from(routeType: model.response.routes[departure.chateauId]?[departure.routeId]?.routeType)
            }
        }
        let set = Set(routeModes + stationModes)
        return TransitDisplayMode.allCases.filter(set.contains)
    }

    private var nearbyTimezone: String? {
        model.response.longDistance.min(by: { $0.distanceM < $1.distanceM })?.timezone
            ?? model.response.stops.values.lazy.compactMap { $0.values.first?.timezone }.first
    }

    private var listItems: [NearbyListItem] {
        let routes = model.response.local.compactMap { group -> NearbyListItem? in
            guard selectedModes.contains(TransitDisplayMode.from(routeType: group.routeType)), !group.headsigns.isEmpty else { return nil }
            return .route(group, model.response.stops[group.chateauId] ?? [:])
        }

        let stations = model.response.longDistance.compactMap { group -> NearbyListItem? in
            let departures = group.departures.filter { departure in
                guard departure.lastStop != true else { return false }
                let routeType = model.response.routes[departure.chateauId]?[departure.routeId]?.routeType
                return selectedModes.contains(TransitDisplayMode.from(routeType: routeType ?? 2))
            }
            return departures.isEmpty ? nil : .station(group, departures)
        }
        .sorted { $0.distance < $1.distance }

        var leading: [NearbyListItem] = []
        var mixed = routes
        if let closest = stations.first, closest.distance < 1_000 {
            leading = [closest]
            mixed.append(contentsOf: stations.dropFirst())
        } else {
            mixed.append(contentsOf: stations)
        }

        switch sortMode {
        case .distance:
            mixed.sort { $0.distance < $1.distance }
        case .alphabetic:
            mixed.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return leading + mixed
    }

    private var requestKey: String {
        guard let origin = lockedOrigin else { return "no-origin|\(reloadNonce)" }
        let time = isNow ? "now" : String(Int64(selectedDate.timeIntervalSince1970 / 60) * 60)
        return "\(origin.latitude)|\(origin.longitude)|\(time)|\(reloadNonce)"
    }

    private func lockFirstLocationIfNeeded() {
        guard fixedOrigin == nil, lockedOrigin == nil, let coordinate = locationManager.lastKnownLocation else { return }
        lockedOrigin = coordinate
        reloadNonce += 1
    }

    private func dropPinAtMapCenter() {
        guard let coordinate = mapCenterCoordinate() else { return }
        pinActive = true
        pickedCoordinate = coordinate
        lockedOrigin = coordinate
        reloadNonce += 1
    }

    private func centerPinOnMap() {
        guard let coordinate = pickedCoordinate else { return }
        viewObject.camera = .center(coordinate, zoom: max(viewObject.currZoom, 12))
    }

    private func mapCenterCoordinate() -> CLLocationCoordinate2D? {
        let bounds = viewObject.visibleCoordinateBounds
        let latitude = (bounds.ne.latitude + bounds.sw.latitude) / 2
        let longitude = (bounds.ne.longitude + bounds.sw.longitude) / 2
        guard latitude.isFinite, longitude.isFinite,
              abs(latitude) <= 90, abs(longitude) <= 180,
              latitude != 0 || longitude != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func updateFromDraggedPin() {
        guard fixedOrigin == nil, pinActive, let pickedCoordinate else { return }
        lockedOrigin = pickedCoordinate
        reloadNonce += 1
    }
}

private struct NearbyStationCard: View {
    let group: NearbyStationGroup
    let departures: [NearbyStationDeparture]
    let routeMap: [String: [String: NearbyRouteInfo]]

    @EnvironmentObject private var viewObject: viewObject

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                openStation()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.stationName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(TransitFormatting.distance(group.distanceM))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if group.osmStationId != nil {
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            Divider()

            ForEach(visibleDepartures) { departure in
                NearbyStationDepartureRow(
                    departure: departure,
                    routeInfo: routeMap[departure.chateauId]?[departure.routeId],
                    timezoneID: group.timezone
                )
                if departure.id != visibleDepartures.last?.id {
                    Divider().padding(.leading, 42)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.quaternary) }
    }

    private var visibleDepartures: [NearbyStationDeparture] {
        Array(departures.sorted(by: departureSort).prefix(10))
    }

    private func departureSort(_ lhs: NearbyStationDeparture, _ rhs: NearbyStationDeparture) -> Bool {
        (lhs.effectiveDeparture ?? .max) < (rhs.effectiveDeparture ?? .max)
    }

    private func openStation() {
        if let id = group.osmStationId {
            viewObject.push(.osmStation(
                osmStationID: String(id),
                stationName: group.stationName,
                modeType: "rail",
                latitude: group.lat,
                longitude: group.lon
            ))
        } else if let first = departures.first {
            viewObject.push(.stop(chateauID: first.chateauId, stopID: first.stopId))
        }
    }
}

private struct NearbyStationDepartureRow: View {
    let departure: NearbyStationDeparture
    let routeInfo: NearbyRouteInfo?
    let timezoneID: String?

    @EnvironmentObject private var viewObject: viewObject

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            NearbyStationDepartureTimeView(
                departure: departure,
                timezoneID: timezoneID
            )

            Button {
                viewObject.push(.route(chateauID: departure.chateauId, routeID: departure.routeId))
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
                openTrip()
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(departure.finalStationName ?? departure.headsign)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(departure.cancelled == true ? .red : .primary)
                            .strikethrough(departure.cancelled == true)
                            .lineLimit(1)

                        if let tripShortName = departure.tripShortName, !tripShortName.isEmpty {
                            Text(tripShortName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let platformText {
                        Text(platformText)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }

    private var platformText: String? {
        guard let raw = departure.platform?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let value = raw
            .replacingOccurrences(of: "Track", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Platform", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? raw : value
    }

    private func openTrip() {
        viewObject.push(.singleTrip(
            chateauID: departure.chateauId,
            tripID: departure.tripId,
            routeID: departure.routeId,
            startTime: nil,
            startDate: departure.serviceDate,
            vehicleID: nil,
            routeType: routeInfo?.routeType
        ))
    }
}

private struct NearbyStationDepartureTimeView: View {
    let departure: NearbyStationDeparture
    let timezoneID: String?

    private var scheduledTime: Int64? {
        departure.scheduledDeparture ?? departure.scheduledArrival
    }

    private var realtimeTime: Int64? {
        departure.realtimeDeparture ?? departure.realtimeArrival
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let scheduledTime {
                Text(TransitFormatting.date(scheduledTime, timezoneID: timezoneID))
                    .font((realtimeTime != nil && realtimeTime != scheduledTime)
                        ? .caption.monospacedDigit()
                        : .subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(
                        realtimeTime != nil && realtimeTime != scheduledTime
                            ? Color.secondary
                            : Color.primary
                    )
            }

            if let realtimeTime, realtimeTime != scheduledTime {
                Text(TransitFormatting.date(realtimeTime, timezoneID: timezoneID))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }

            if scheduledTime == nil, realtimeTime == nil {
                Text("—")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let delay = TransitFormatting.delay(scheduled: scheduledTime, realtime: realtimeTime) {
                Text(delay)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.orange)
            }

            if let relative = TransitFormatting.relative(realtimeTime ?? scheduledTime) {
                Text(relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 68, alignment: .leading)
    }
}

private struct NearbyRouteCard: View {
    let group: NearbyRouteGroup
    let stops: [String: NearbyStopInfo]
    let timezoneID: String?

    @EnvironmentObject private var viewObject: viewObject

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Button {
                    viewObject.push(.route(chateauID: group.chateauId, routeID: group.routeId))
                } label: {
                    HStack(spacing: 8) {
                        TransitRouteBadge(
                            shortName: group.shortName,
                            longName: group.longName,
                            colorHex: group.color,
                            textColorHex: group.textColor
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            if let longName = group.longName, longName != group.shortName {
                                Text(longName).font(.subheadline.weight(.medium)).lineLimit(1)
                            }
                            if let agencyName = group.agencyName {
                                Text(agencyName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(TransitFormatting.distance(group.closestDistance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(group.headsigns.keys.sorted(), id: \.self) { headsign in
                if let departures = group.headsigns[headsign] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(headsign)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        ForEach(Array(departures.filter { $0.lastStop != true }.sorted(by: localSort).prefix(3))) { departure in
                            NearbyLocalDepartureRow(
                                departure: departure,
                                group: group,
                                stop: stops[departure.stopId],
                                timezoneID: stops[departure.stopId]?.timezone ?? timezoneID
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.quaternary) }
    }

    private func localSort(_ lhs: NearbyLocalDeparture, _ rhs: NearbyLocalDeparture) -> Bool {
        (lhs.effectiveDeparture ?? .max) < (rhs.effectiveDeparture ?? .max)
    }
}

private struct NearbyLocalDepartureRow: View {
    let departure: NearbyLocalDeparture
    let group: NearbyRouteGroup
    let stop: NearbyStopInfo?
    let timezoneID: String?

    @EnvironmentObject private var viewObject: viewObject

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewObject.push(.stop(chateauID: group.chateauId, stopID: departure.stopId))
            } label: {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 28)
            }
            .buttonStyle(.plain)

            Button {
                viewObject.push(.singleTrip(
                    chateauID: group.chateauId,
                    tripID: departure.tripId,
                    routeID: group.routeId,
                    startTime: nil,
                    startDate: departure.serviceDate,
                    vehicleID: nil,
                    routeType: group.routeType
                ))
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stop?.name ?? departure.stopName ?? departure.stopId)
                            .font(.subheadline)
                            .foregroundStyle(departure.cancelled == true ? .red : .primary)
                            .strikethrough(departure.cancelled == true)
                            .lineLimit(1)
                        if let platform = departure.platform, !platform.isEmpty {
                            Text("Platform \(platform)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(TransitFormatting.date(departure.effectiveDeparture, timezoneID: timezoneID))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        if let relative = TransitFormatting.relative(departure.effectiveDeparture) {
                            Text(relative).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

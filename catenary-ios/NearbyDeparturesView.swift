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
    var label: LocalizedStringKey { self == .distance ? "Distance" : "Name" }
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
    let drawerHeight: CGFloat?
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
        drawerHeight: CGFloat? = nil,
        pinActive: Binding<Bool> = .constant(false),
        pickedCoordinate: Binding<CLLocationCoordinate2D?> = .constant(nil)
    ) {
        self.locationManager = locationManager
        self.fixedOrigin = fixedOrigin
        self.drawerHeight = drawerHeight
        _pinActive = pinActive
        _pickedCoordinate = pickedCoordinate
        _lockedOrigin = State(
            initialValue: fixedOrigin ?? (pinActive.wrappedValue ? pickedCoordinate.wrappedValue : nil)
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
            if fixedOrigin == nil {
                controls
            } else {
                Label("Departures near selected location", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let origin = lockedOrigin {
                HStack(spacing: 6) {
                    TransitTimePicker(
                        selectedDate: $selectedDate,
                        isNow: $isNow,
                        timezoneID: nearbyTimezone,
                        onCommit: { date, now in
                            isNow = now
                            if let date { selectedDate = date }
                            reloadNonce += 1
                        },
                        compact: true
                    )

                    if let serverMs = model.response.debug?.totalTimeMs {
                        Text("\(serverMs) ms")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }

                if availableModes.count > 1 {
                    TransitModePicker(
                        availableModes: availableModes,
                        selectedModes: $selectedModes,
                        compact: true
                    )
                }

                if model.isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                }

                content(origin: origin)
            } else {
                CatenaryUnavailableView {
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
            .opacity(drawerExpansionProgress)
            .allowsHitTesting(drawerExpansionProgress > 0.9)
            .accessibilityHidden(drawerExpansionProgress < 0.5)

            if usesCompactDrawerSummary {
                compactSummary
                    .opacity(1 - drawerExpansionProgress)
                    .allowsHitTesting(false)
                    .accessibilityHidden(drawerExpansionProgress >= 0.5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .task {
            if fixedOrigin == nil {
                locationManager.checkLocationAuthorization()
                lockFirstLocationIfNeeded()
            }
        }
        .catenaryOnChange(of: locationManager.lastKnownLocation?.latitude) { _, _ in
            lockFirstLocationIfNeeded()
        }
        .catenaryOnChange(of: locationManager.lastKnownLocation?.longitude) { _, _ in
            lockFirstLocationIfNeeded()
        }
        .catenaryOnChange(of: pinActive) { _, active in
            guard fixedOrigin == nil else { return }
            if active, let pickedCoordinate {
                lockedOrigin = pickedCoordinate
                reloadNonce += 1
            } else {
                lockedOrigin = locationManager.lastKnownLocation
                reloadNonce += 1
            }
        }
        .catenaryOnChange(of: pickedCoordinate?.latitude) { _, _ in
            updateFromDraggedPin()
        }
        .catenaryOnChange(of: pickedCoordinate?.longitude) { _, _ in
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
        HStack(spacing: 6) {
            if pinActive {
                pinControlButton
                locationControlButton
            } else {
                locationControlButton
                pinControlButton
            }

            if pinActive {
                Button {
                    centerPinOnMap()
                } label: {
                    Image(systemName: "scope")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Center pin on map")
            }

            Spacer()

            NearbySortToggle(selection: $sortMode)
        }
        .font(.caption)
        .controlSize(.small)
    }

    private var locationControlButton: some View {
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
    }

    private var pinControlButton: some View {
        Button {
            dropPinAtMapCenter()
        } label: {
            Label(
                pinActive
                    ? LocalizedStringKey("Move pin")
                    : LocalizedStringKey("Drop pin"),
                systemImage: "mappin.and.ellipse"
            )
        }
        .buttonStyle(.bordered)
    }

    private var usesCompactDrawerSummary: Bool {
        fixedOrigin == nil && drawerHeight != nil
    }

    private var drawerExpansionProgress: CGFloat {
        guard usesCompactDrawerSummary, let drawerHeight else { return 1 }

        // The drawer drag gesture begins after five points. Fade the compact
        // summary over the next few points so the full controls are already
        // visible before the drag has meaningfully expanded the drawer.
        return min(max((drawerHeight - 80) / 14, 0), 1)
    }

    private var compactSummary: some View {
        NearbyCompactSummary(
            pinActive: pinActive,
            station: compactStation,
            stationDepartures: compactStation.map { compactStationDepartures(for: $0) } ?? [],
            routes: compactRoutes,
            stops: model.response.stops,
            fallbackTimezoneID: nearbyTimezone,
            isLoading: model.isLoading && !model.hasLoaded
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactStation: NearbyStationGroup? {
        model.response.longDistance
            .filter { !compactStationDepartures(for: $0).isEmpty }
            .min { $0.distanceM < $1.distanceM }
    }

    private func compactStationDepartures(for group: NearbyStationGroup) -> [NearbyStationDeparture] {
        group.departures
            .filter { departure in
                guard departure.lastStop != true else { return false }
                let routeType = model.response.routes[departure.chateauId]?[departure.routeId]?.routeType
                return selectedModes.contains(TransitDisplayMode.from(routeType: routeType ?? 2))
            }
            .sorted { ($0.effectiveDeparture ?? .max) < ($1.effectiveDeparture ?? .max) }
    }

    private var compactRoutes: [NearbyRouteGroup] {
        Array(
            model.response.local
                .filter { group in
                    selectedModes.contains(TransitDisplayMode.from(routeType: group.routeType))
                        && isCompactLocalRouteType(group.routeType)
                        && group.headsigns.values.contains { departures in
                            departures.contains { $0.lastStop != true }
                        }
                }
                .sorted { $0.closestDistance < $1.closestDistance }
                .prefix(3)
        )
    }

    private func isCompactLocalRouteType(_ routeType: Int?) -> Bool {
        guard let routeType else { return true }

        switch routeType {
        case 0, 1, 3, 11,
             400...499,
             700...799,
             800...899,
             900...999:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func content(origin: CLLocationCoordinate2D) -> some View {
        if let errorMessage = model.errorMessage, !model.hasLoaded {
            CatenaryUnavailableView("Unable to load departures", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if listItems.isEmpty && model.hasLoaded && !model.isLoading {
            CatenaryUnavailableView("No nearby departures", systemImage: "clock.badge.xmark")
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

private struct NearbyCompactSummary: View {
    let pinActive: Bool
    let station: NearbyStationGroup?
    let stationDepartures: [NearbyStationDeparture]
    let routes: [NearbyRouteGroup]
    let stops: [String: [String: NearbyStopInfo]]
    let fallbackTimezoneID: String?
    let isLoading: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: pinActive ? "mappin.and.ellipse" : "location.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 12, height: 10)

                    Text("Nearby departures")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .frame(height: 10)

                if let station {
                    NearbyCompactStationRow(
                        group: station,
                        departures: stationDepartures,
                        now: context.date
                    )
                    .frame(height: 13)
                }

                ForEach(routes) { route in
                    NearbyCompactRouteRow(
                        group: route,
                        stops: stops[route.chateauId] ?? [:],
                        fallbackTimezoneID: fallbackTimezoneID,
                        now: context.date
                    )
                    .frame(height: 13)
                }

                if station == nil, routes.isEmpty {
                    Text(isLoading ? "Loading departures..." : "No nearby departures")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: 13)
                }
            }
        }
    }
}

private struct NearbyCompactStationRow: View {
    let group: NearbyStationGroup
    let departures: [NearbyStationDeparture]
    let now: Date

    var body: some View {
        HStack(spacing: 4) {
            Text(group.stationName)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 92, alignment: .leading)

            ForEach(Array(visibleDepartures.enumerated()), id: \.offset) { index, departure in
                let destination = NearbyCompactFormatting.destination(
                    departure.finalStationName ?? departure.headsign
                )
                if let time = NearbyCompactFormatting.time(
                    departure.effectiveDeparture,
                    timezoneID: group.timezone,
                    now: now
                ) {
                    (Text(time)
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                    + Text(" -> \(destination)")
                        .font(.system(size: 9)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(index == 0 ? 1 : 0)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var visibleDepartures: [NearbyStationDeparture] {
        Array(
            departures
                .sorted { ($0.effectiveDeparture ?? .max) < ($1.effectiveDeparture ?? .max) }
                .prefix(2)
        )
    }
}

private struct NearbyCompactHeadsign {
    let name: String
    let departures: [NearbyLocalDeparture]
}

private struct NearbyCompactRouteRow: View {
    let group: NearbyRouteGroup
    let stops: [String: NearbyStopInfo]
    let fallbackTimezoneID: String?
    let now: Date

    var body: some View {
        HStack(spacing: 3) {
            NearbyCompactRouteBadge(group: group)

            ForEach(Array(headsigns.enumerated()), id: \.offset) { index, headsign in
                if index > 0 {
                    Text("|")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }

                NearbyCompactHeadsignSummary(
                    headsign: headsign,
                    stops: stops,
                    fallbackTimezoneID: fallbackTimezoneID,
                    now: now
                )
            }

            Spacer(minLength: 0)
        }
    }

    private var headsigns: [NearbyCompactHeadsign] {
        Array(
            group.headsigns
                .compactMap { entry -> NearbyCompactHeadsign? in
                    let (name, departures) = entry
                    let visible = departures
                        .filter { $0.lastStop != true }
                        .sorted { ($0.effectiveDeparture ?? .max) < ($1.effectiveDeparture ?? .max) }
                    guard !visible.isEmpty else { return nil }
                    return NearbyCompactHeadsign(name: name, departures: visible)
                }
                .sorted {
                    ($0.departures.first?.effectiveDeparture ?? .max)
                        < ($1.departures.first?.effectiveDeparture ?? .max)
                }
                .prefix(2)
        )
    }
}

private struct NearbyCompactHeadsignSummary: View {
    let headsign: NearbyCompactHeadsign
    let stops: [String: NearbyStopInfo]
    let fallbackTimezoneID: String?
    let now: Date

    var body: some View {
        HStack(spacing: 2) {
            Text(NearbyCompactFormatting.destination(headsign.name))
                .font(.system(size: 8.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 68, alignment: .leading)

            Text(timeList)
                .font(.system(size: 8.5, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var timeList: String {
        let timestamps = headsign.departures
            .compactMap(\.effectiveDeparture)
        let timezoneID = headsign.departures.first.flatMap { departure in
            stops[departure.stopId]?.timezone
        } ?? fallbackTimezoneID
        return NearbyCompactFormatting.times(
            timestamps,
            timezoneID: timezoneID,
            now: now
        )
    }
}

private struct NearbyCompactRouteBadge: View {
    let group: NearbyRouteGroup

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 3)
            .frame(width: 34, height: 11)
            .background(Color.primary.opacity(0.1), in: Capsule())
            .overlay {
                Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }

    private var label: String {
        let value = group.shortName ?? group.longName ?? group.routeId
        let cleaned = value.replacingOccurrences(of: " Line", with: "")
        return String(cleaned.prefix(6))
    }
}

private enum NearbyCompactFormatting {
    static func destination(_ value: String) -> String {
        value
            .replacingOccurrences(of: " Underground Station", with: "")
            .replacingOccurrences(of: " Station", with: "")
    }

    static func time(_ timestamp: Int64?, timezoneID: String?, now: Date) -> String? {
        guard let timestamp else { return nil }
        let diff = TimeInterval(timestamp) - now.timeIntervalSince1970
        if diff > -60, diff <= 3_600 {
            return "\(max(Int(ceil(diff / 60)), 0))min"
        }
        return clock(timestamp, timezoneID: timezoneID)
    }

    static func times(_ timestamps: [Int64], timezoneID: String?, now: Date) -> String {
        let visible = Array(timestamps.prefix(3))
        guard !visible.isEmpty else { return "-" }

        let diffs = visible.map { TimeInterval($0) - now.timeIntervalSince1970 }
        if diffs.allSatisfy({ $0 > -60 && $0 <= 3_600 }) {
            return diffs
                .map { String(max(Int(ceil($0 / 60)), 0)) }
                .joined(separator: ",") + "min"
        }

        return visible
            .compactMap { time($0, timezoneID: timezoneID, now: now) }
            .joined(separator: ",")
    }

    private static func clock(_ timestamp: Int64, timezoneID: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        if let timezoneID, let timezone = TimeZone(identifier: timezoneID) {
            formatter.timeZone = timezone
        } else {
            formatter.timeZone = .current
        }
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
}

private struct NearbySortToggle: View {
    @Binding var selection: NearbySortMode

    var body: some View {
        HStack(spacing: 0) {
            sortButton(for: .alphabetic) {
                Text("A–Z")
                    .font(.caption2.weight(.bold))
            }

            sortButton(for: .distance) {
                Image(systemName: "ruler")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(1)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private func sortButton<Label: View>(
        for mode: NearbySortMode,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            selection = mode
        } label: {
            label()
                .frame(width: 28, height: 28)
                .foregroundStyle(selection == mode ? Color.accentColor : Color.primary)
                .background {
                    if selection == mode {
                        Circle().fill(Color.accentColor.opacity(0.2))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(selection == mode ? .isSelected : [])
    }
}

private struct NearbyStationCard: View {
    let group: NearbyStationGroup
    let departures: [NearbyStationDeparture]
    let routeMap: [String: [String: NearbyRouteInfo]]

    @EnvironmentObject private var viewObject: viewObject
    @AppStorage("usUnits") private var usUnits = false

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
                        Text(TransitFormatting.distance(group.distanceM, useImperial: usUnits))
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
                    timezoneID: group.timezone,
                    stationCoordinate: CLLocationCoordinate2D(
                        latitude: group.lat,
                        longitude: group.lon
                    )
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
    let stationCoordinate: CLLocationCoordinate2D

    var body: some View {
        StationTrainDepartureRowCompact(
            event: stopEvent,
            routeInfo: convertedRouteInfo,
            agency: convertedAgency,
            timezoneID: timezoneID,
            now: Date(),
            layout: StopDeparturePresentation.layout(
                for: stationCoordinate,
                chateauID: departure.chateauId
            ),
            trainDisplayName: departure.tripShortName,
            showAgencyName: true
        )
    }

    private var effectiveRealtimeDeparture: Int64? {
        if let realtimeDeparture = departure.realtimeDeparture { return realtimeDeparture }
        if let scheduledDeparture = departure.scheduledDeparture,
           let realtimeArrival = departure.realtimeArrival,
           realtimeArrival > scheduledDeparture {
            return realtimeArrival
        }
        return nil
    }

    private var stopEvent: StopEvent {
        StopEvent(
            chateau: departure.chateauId,
            tripId: departure.tripId,
            routeId: departure.routeId,
            serviceDate: departure.serviceDate,
            headsign: departure.headsign,
            stopId: departure.stopId,
            scheduledDeparture: departure.scheduledDeparture,
            realtimeDeparture: effectiveRealtimeDeparture,
            scheduledArrival: departure.scheduledArrival,
            realtimeArrival: departure.realtimeArrival,
            tripShortName: departure.tripShortName,
            lastStop: departure.lastStop,
            platformStringRealtime: departure.platform,
            vehicleNumber: nil,
            delaySeconds: nil,
            tripCancelled: departure.cancelled,
            stopCancelled: false,
            tripDeleted: false,
            routeType: routeInfo?.routeType,
            timezone: timezoneID,
            distanceM: nil,
            finalStationName: departure.finalStationName
        )
    }

    private var convertedRouteInfo: StopRouteInfo? {
        guard let routeInfo else { return nil }
        return StopRouteInfo(
            color: routeInfo.color,
            textColor: routeInfo.textColor,
            shortName: routeInfo.shortName,
            longName: routeInfo.longName,
            shapesList: nil,
            routeType: routeInfo.routeType,
            agencyId: nil
        )
    }

    private var convertedAgency: StopAgencyInfo? {
        guard let agencyName = routeInfo?.agencyName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !agencyName.isEmpty else { return nil }
        return StopAgencyInfo(
            agencyName: agencyName,
            agencyUrl: nil,
            agencyTimezone: timezoneID,
            agencyLang: nil,
            agencyPhone: nil,
            agencyFareUrl: nil
        )
    }
}

private struct NearbyStationDepartureTimeView: View {
    let departure: NearbyStationDeparture
    let timezoneID: String?

    @AppStorage("showSeconds") private var showSeconds = false
    @AppStorage("showCountdownsUnder1h") private var showCountdownsUnder1h = false

    private var scheduledTime: Int64? {
        departure.scheduledDeparture ?? departure.scheduledArrival
    }

    private var realtimeTime: Int64? {
        departure.realtimeDeparture ?? departure.realtimeArrival
    }

    private var targetTime: Int64? {
        realtimeTime ?? scheduledTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let scheduledTime {
                Text(TransitFormatting.date(
                    scheduledTime,
                    timezoneID: timezoneID,
                    showSeconds: showSeconds
                ))
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
                Text(TransitFormatting.date(
                    realtimeTime,
                    timezoneID: timezoneID,
                    showSeconds: showSeconds
                ))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }

            if scheduledTime == nil, realtimeTime == nil {
                Text("—")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let scheduledTime,
               let realtimeTime,
               realtimeTime != scheduledTime {
                DelayDiff(
                    diff: realtimeTime - scheduledTime,
                    showSeconds: showSeconds,
                    fontSizeOfPolarity: 10,
                    useSymbolSign: true,
                    hideMinUnits: !showSeconds
                )
            }

            if showCountdownsUnder1h,
               let targetTime,
               targetTime - Int64(Date().timeIntervalSince1970) > -60,
               targetTime - Int64(Date().timeIntervalSince1970) < 3_600 {
                SelfUpdatingDiffTimer(
                    targetTimeSeconds: targetTime,
                    showBrackets: false,
                    showSeconds: showSeconds,
                    showDays: false,
                    showPlus: false,
                    numSize: 11,
                    unitSize: 9,
                    color: .secondary
                )
            }
        }
        .frame(width: showSeconds ? 82 : 68, alignment: .leading)
    }
}

private struct NearbyRouteCard: View {
    let group: NearbyRouteGroup
    let stops: [String: NearbyStopInfo]
    let timezoneID: String?

    @EnvironmentObject private var viewObject: viewObject
    @AppStorage("usUnits") private var usUnits = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Button {
                    viewObject.push(.route(chateauID: group.chateauId, routeID: group.routeId))
                } label: {
                    HStack(spacing: 8) {
                        if group.chateauId == NationalRailUtils.chateauID,
                           routeDisplayName == nil {
                            NationalRailAgencyLabel(
                                agencyID: nil,
                                agencyName: group.agencyName
                            )
                        } else {
                            TransitRouteBadge(
                                shortName: group.shortName,
                                longName: group.longName,
                                colorHex: group.color,
                                textColorHex: group.textColor,
                                chateauID: group.chateauId
                            )
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            if let routeDisplayName, routeDisplayName != group.shortName {
                                Text(routeDisplayName)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            if let resolvedAgencyName,
                               resolvedAgencyName != routeDisplayName,
                               !(group.chateauId == NationalRailUtils.chateauID && routeDisplayName == nil) {
                                Text(resolvedAgencyName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(TransitFormatting.distance(group.closestDistance, useImperial: usUnits))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(group.headsigns.keys.sorted(), id: \.self) { headsign in
                if let departures = group.headsigns[headsign] {
                    let visibleDepartures = departures
                        .filter { $0.lastStop != true }
                        .sorted(by: localSort)

                    if !visibleDepartures.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.forward")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(cleanedHeadsign(headsign))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)

                                if let firstDeparture = visibleDepartures.first {
                                    Button {
                                        viewObject.push(.stop(
                                            chateauID: group.chateauId,
                                            stopID: firstDeparture.stopId
                                        ))
                                    } label: {
                                        Label(stopName(for: firstDeparture), systemImage: "mappin")
                                            .font(.caption)
                                            .lineLimit(1)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(
                                                Color(uiColor: .tertiarySystemBackground),
                                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 2) {
                                    ForEach(visibleDepartures) { departure in
                                        NearbyLocalDeparturePill(
                                            departure: departure,
                                            group: group,
                                            timezoneID: stops[departure.stopId]?.timezone ?? timezoneID
                                        )
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.quaternary) }
    }

    private var resolvedAgencyName: String? {
        if group.chateauId == NationalRailUtils.chateauID {
            return NationalRailUtils.resolvedAgencyName(
                agencyID: nil,
                agencyName: group.agencyName
            )
        }
        guard let value = group.agencyName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private var routeDisplayName: String? {
        for value in [group.longName, group.shortName] {
            if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func localSort(_ lhs: NearbyLocalDeparture, _ rhs: NearbyLocalDeparture) -> Bool {
        (lhs.effectiveDeparture ?? .max) < (rhs.effectiveDeparture ?? .max)
    }

    private func cleanedHeadsign(_ value: String) -> String {
        value
            .replacingOccurrences(of: " Underground Station", with: "")
            .replacingOccurrences(of: " Station", with: "")
    }

    private func stopName(for departure: NearbyLocalDeparture) -> String {
        stops[departure.stopId]?.name ?? departure.stopName ?? departure.stopId
    }
}

private struct NearbyLocalDeparturePill: View {
    let departure: NearbyLocalDeparture
    let group: NearbyRouteGroup
    let timezoneID: String?

    @EnvironmentObject private var viewObject: viewObject
    @AppStorage("showSeconds") private var showSeconds = false

    private var scheduledTime: Int64? {
        departure.departureSchedule ?? departure.arrivalSchedule
    }

    private var realtimeTime: Int64? {
        departure.departureRealtime ?? departure.arrivalRealtime
    }

    private var targetTime: Int64? {
        departure.effectiveDeparture
    }

    var body: some View {
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
            VStack(spacing: 1) {
                if let targetTime {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        TimeDiff(
                            diff: TimeInterval(targetTime) - context.date.timeIntervalSince1970,
                            showBrackets: false,
                            showSeconds: showSeconds,
                            showDays: false,
                            showPlus: false,
                            numSize: 12,
                            unitSize: 12,
                            numberFontWeight: .medium,
                            unitFontWeight: .medium
                        )
                    }
                }

                Text(TransitFormatting.date(
                    departure.effectiveDeparture,
                    timezoneID: timezoneID,
                    showSeconds: showSeconds
                ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)

                if departure.cancelled == true {
                    Text("Cancelled")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }

                if let scheduledTime,
                   let realtimeTime,
                   realtimeTime != scheduledTime {
                    DelayDiff(
                        diff: realtimeTime - scheduledTime,
                        showSeconds: showSeconds,
                        fontSizeOfPolarity: 12,
                        valueFontSize: 12,
                        unitFontSize: 12,
                        useSymbolSign: true,
                        hideMinUnits: !showSeconds
                    )
                }

                if let platform = platformText {
                    Text(verbatim: L10n.format(
                        "platform.value",
                        defaultValue: "Platform %@",
                        platform
                    ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(minWidth: showSeconds ? 92 : 64)
            .background(
                Color(uiColor: .tertiarySystemBackground),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
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
}

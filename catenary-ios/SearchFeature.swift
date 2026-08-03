import CoreLocation
import Foundation
import MapLibre
import SwiftUI

// MARK: - Search field

struct SearchLauncher: View {
    let onSearch: () -> Void
    let onSettingsClick: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSearch) {
                HStack(spacing: 8) {
                    Image(.catLogo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)

                    Text("Search Here")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.leading, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")

            Button(action: onSettingsClick) {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Settings")
        }
        .frame(height: 48)
        .catenarySearchBarSurface()
    }
}

struct CatenarySearchBar: View {
    @ObservedObject var viewModel: SearchViewModel
    let focus: FocusState<Bool>.Binding
    let isActive: Bool
    let onQueryChange: (String) -> Void
    let onClose: () -> Void
    let onSettingsClick: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isActive {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close search")
                } else {
                    Image(.catLogo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .accessibilityLabel("Catenary logo")
                }
            }
            .frame(width: 48, height: 48)

            TextField("Search Here", text: $viewModel.query)
                .font(.system(size: 16))
                .lineLimit(1)
                .submitLabel(.search)
                .focused(focus)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 8)

            if viewModel.query.isEmpty && !isActive {
                Button(action: onSettingsClick) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Settings")
            }
        }
        .frame(height: 48)
        .catenarySearchBarSurface()
        .onChange(of: viewModel.query) { _, query in
            onQueryChange(query)
        }
    }
}

// MARK: - Search state and networking

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var rows: [SearchRow] = []
    @Published private(set) var isLoading = false

    private let worker = SearchWorker()
    private var searchTask: Task<Void, Never>?
    private var generation = UUID()

    func search(
        query: String,
        userLocation: CLLocationCoordinate2D?,
        mapCenter: CLLocationCoordinate2D
    ) {
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            generation = UUID()
            if !rows.isEmpty {
                rows = []
            }
            if isLoading {
                isLoading = false
            }
            return
        }

        let token = UUID()
        generation = token
        if !isLoading {
            isLoading = true
        }

        let request = SearchRequestContext(
            query: trimmedQuery,
            userLocation: userLocation.map(SearchCoordinate.init),
            mapCenter: SearchCoordinate(mapCenter)
        )
        let worker = self.worker

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            let combinedRows = await worker.perform(request)

            guard let self,
                  self.generation == token,
                  !Task.isCancelled else { return }

            self.rows = combinedRows
            self.isLoading = false
        }
    }

    func reset() {
        searchTask?.cancel()
        searchTask = nil
        generation = UUID()

        if !query.isEmpty {
            query = ""
        }
        if !rows.isEmpty {
            rows = []
        }
        if isLoading {
            isLoading = false
        }
    }

    nonisolated fileprivate static func fetchCatenary(
        _ request: SearchRequestContext
    ) async -> SearchCatenaryResponse? {
        var components = URLComponents(string: "https://birch.catenarymaps.org/text_search_v1")
        var items = [
            URLQueryItem(name: "text", value: request.query),
            URLQueryItem(name: "map_lat", value: String(request.mapCenter.latitude)),
            URLQueryItem(name: "map_lon", value: String(request.mapCenter.longitude)),
            URLQueryItem(name: "map_z", value: "10")
        ]
        if let userLocation = request.userLocation {
            items.append(URLQueryItem(name: "user_lat", value: String(userLocation.latitude)))
            items.append(URLQueryItem(name: "user_lon", value: String(userLocation.longitude)))
        }
        components?.queryItems = items
        return await fetch(SearchCatenaryResponse.self, url: components?.url)
    }

    nonisolated fileprivate static func fetchCypress(
        _ request: SearchRequestContext
    ) async -> [SearchCypressFeature] {
        var components = URLComponents(string: "https://cypress.catenarymaps.org/v2/search")
        components?.queryItems = [
            URLQueryItem(name: "text", value: request.query),
            URLQueryItem(name: "focus.point.lat", value: String(request.mapCenter.latitude)),
            URLQueryItem(name: "focus.point.lon", value: String(request.mapCenter.longitude)),
            URLQueryItem(name: "focus.point.weight", value: "4")
        ]
        let response = await fetch(SearchCypressResponse.self, url: components?.url)
        return response?.features ?? []
    }

    nonisolated fileprivate static func fetchOsmStations(
        _ request: SearchRequestContext
    ) async -> [SearchOsmStationResult] {
        var components = URLComponents(string: "https://birch.catenarymaps.org/osm_station_search")
        components?.queryItems = [URLQueryItem(name: "text", value: request.query)]
        let response = await fetch(SearchOsmStationSearchResponse.self, url: components?.url)
        return response?.results ?? []
    }

    nonisolated fileprivate static func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        url: URL?
    ) async -> T? {
        guard let url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }

    nonisolated fileprivate static func buildCombinedRows(
        catenaryResults: SearchCatenaryResponse?,
        cypressResults: [SearchCypressFeature],
        osmStationResults: [SearchOsmStationResult],
        userLocation: SearchCoordinate?
    ) -> [SearchRow] {
        var rows: [SearchRow] = []

        let osmTotal = max(osmStationResults.count, 1)
        for (index, station) in osmStationResults.prefix(10).enumerated() {
            rows.append(.osmStation(station, score: rankToUnitScore(index: index, total: osmTotal) * 2.0))
        }

        for feature in cypressResults.prefix(10) {
            let confidence = feature.properties?.confidence ?? 0
            let score = min(max(confidence / 1_000, 0), 1) * 2.0
            rows.append(.cypress(feature, score: score))
        }

        if let section = catenaryResults?.routesSection {
            let rankings = Array((section.ranking ?? []).prefix(10))
            let total = max(rankings.count, 1)
            for (index, ranking) in rankings.enumerated() {
                guard let chateau = ranking.chateau,
                      let gtfsID = ranking.gtfsID,
                      let route = section.routes?[chateau]?[gtfsID] else {
                    continue
                }
                let agency = route.agencyID.flatMap { section.agencies?[chateau]?[$0] }
                rows.append(
                    .route(
                        ranking: ranking,
                        route: route,
                        agency: agency,
                        score: rankToUnitScore(index: index, total: total)
                    )
                )
            }
        }

        if let section = catenaryResults?.stopsSection {
            let rankings = Array((section.ranking ?? []).prefix(10))
            let total = max(rankings.count, 1)
            for (index, ranking) in rankings.enumerated() {
                guard let chateau = ranking.chateau,
                      let gtfsID = ranking.gtfsID,
                      let stop = section.stops?[chateau]?[gtfsID],
                      stop.parentStation == nil else {
                    continue
                }

                let routes = (stop.routes ?? []).compactMap { section.routes?[chateau]?[$0] }
                let agencyNames = Array(
                    Set(
                        routes.compactMap { route in
                            route.agencyID.flatMap { section.agencies?[chateau]?[$0]?.agencyName }
                        }
                    )
                ).sorted()

                let distanceMetres: Double?
                if let userLocation, let point = stop.point {
                    distanceMetres = haversineDistance(
                        from: userLocation,
                        to: SearchCoordinate(latitude: point.y, longitude: point.x)
                    )
                } else {
                    distanceMetres = nil
                }

                rows.append(
                    .stop(
                        ranking: ranking,
                        stop: stop,
                        routes: routes,
                        agencyNames: agencyNames,
                        distanceMetres: distanceMetres,
                        score: rankToUnitScore(index: index, total: total)
                    )
                )
            }
        }

        return rows.sorted { $0.weightedScore > $1.weightedScore }
    }

    nonisolated fileprivate static func rankToUnitScore(index: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(total - index) / Double(total), 0), 1)
    }

    nonisolated fileprivate static func haversineDistance(
        from: SearchCoordinate,
        to: SearchCoordinate
    ) -> Double {
        let earthRadius = 6_371_000.0
        let latitude1 = from.latitude * .pi / 180
        let latitude2 = to.latitude * .pi / 180
        let latitudeDelta = (to.latitude - from.latitude) * .pi / 180
        let longitudeDelta = (to.longitude - from.longitude) * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

private actor SearchWorker {
    func perform(_ request: SearchRequestContext) async -> [SearchRow] {
        async let catenary = SearchViewModel.fetchCatenary(request)
        async let cypress = SearchViewModel.fetchCypress(request)
        async let osmStations = SearchViewModel.fetchOsmStations(request)

        let results = await (catenary, cypress, osmStations)
        guard !Task.isCancelled else { return [] }

        return SearchViewModel.buildCombinedRows(
            catenaryResults: results.0,
            cypressResults: results.1,
            osmStationResults: results.2,
            userLocation: request.userLocation
        )
    }
}

private struct SearchRequestContext: Sendable {
    let query: String
    let userLocation: SearchCoordinate?
    let mapCenter: SearchCoordinate
}

private struct SearchCoordinate: Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }
}

// MARK: - Combined result rows

enum SearchRow: Identifiable, Sendable {
    case cypress(SearchCypressFeature, score: Double)
    case osmStation(SearchOsmStationResult, score: Double)
    case route(
        ranking: SearchRouteRanking,
        route: SearchRouteInfo,
        agency: SearchAgency?,
        score: Double
    )
    case stop(
        ranking: SearchStopRanking,
        stop: SearchStopInfo,
        routes: [SearchRouteInfo],
        agencyNames: [String],
        distanceMetres: Double?,
        score: Double
    )

    var id: String {
        switch self {
        case let .cypress(feature, _):
            return "cypress|\(feature.properties?.id ?? feature.fallbackID)"
        case let .osmStation(station, _):
            return "osm|\(station.osmID ?? station.fallbackID)"
        case let .route(ranking, _, _, _):
            return "route|\(ranking.chateau ?? "")|\(ranking.gtfsID ?? "")"
        case let .stop(ranking, _, _, _, _, _):
            return "stop|\(ranking.chateau ?? "")|\(ranking.gtfsID ?? "")"
        }
    }

    var weightedScore: Double {
        switch self {
        case let .cypress(_, score), let .osmStation(_, score):
            return score
        case let .route(_, _, _, score), let .stop(_, _, _, _, _, score):
            return score
        }
    }
}

// MARK: - Results UI

struct CatenarySearchResultsView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onCypressClick: (SearchCypressFeature) -> Void
    let onStopClick: (SearchStopRanking) -> Void
    let onRouteClick: (SearchRouteRanking) -> Void
    let onOsmStationClick: (SearchOsmStationResult) -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.rows) { row in
                        resultRow(row)
                        Divider()
                            .opacity(0.2)
                    }
                }
            }

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ row: SearchRow) -> some View {
        switch row {
        case let .cypress(feature, _):
            SearchResultButton(action: { onCypressClick(feature) }) {
                CypressSearchResultRow(feature: feature)
            }
        case let .osmStation(station, _):
            SearchResultButton(action: { onOsmStationClick(station) }) {
                OsmStationSearchResultRow(station: station)
            }
        case let .route(ranking, route, agency, _):
            SearchResultButton(action: { onRouteClick(ranking) }) {
                RouteSearchResultRow(route: route, agency: agency)
            }
        case let .stop(ranking, stop, routes, agencyNames, distanceMetres, _):
            SearchResultButton(action: { onStopClick(ranking) }) {
                StopSearchResultRow(
                    stop: stop,
                    routes: routes,
                    agencyNames: agencyNames,
                    distanceMetres: distanceMetres
                )
            }
        }
    }
}

private struct SearchResultButton<Content: View>: View {
    let action: () -> Void
    let content: Content

    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CypressSearchResultRow: View {
    let feature: SearchCypressFeature

    var body: some View {
        let properties = feature.properties
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(properties?.displayName ?? L10n.string("Unknown"))
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                Text(properties?.displayTag ?? L10n.string("Place"))
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(properties?.displaySubtitle ?? L10n.string("Place"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct StopSearchResultRow: View {
    let stop: SearchStopInfo
    let routes: [SearchRouteInfo]
    let agencyNames: [String]
    let distanceMetres: Double?

    @AppStorage("usUnits") private var usUnits = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stop.name ?? L10n.string("Unknown stop"))
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let distanceMetres {
                    Text(TransitFormatting.distance(distanceMetres, useImperial: usUnits))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !agencyNames.isEmpty {
                Text(agencyNames.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !routes.isEmpty {
                SearchFlowLayout(spacing: 4) {
                    ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                        TransitRouteBadge(
                            shortName: route.shortName,
                            longName: route.longName,
                            colorHex: route.color,
                            textColorHex: route.textColor
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct RouteSearchResultRow: View {
    let route: SearchRouteInfo
    let agency: SearchAgency?

    var body: some View {
        HStack(spacing: 8) {
            TransitRouteBadge(
                shortName: route.shortName,
                longName: route.longName,
                colorHex: route.color,
                textColorHex: route.textColor
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(route.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                if let longName = route.longName, !longName.isEmpty {
                    Text(longName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let agencyName = agency?.agencyName {
                Text(agencyName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct OsmStationSearchResultRow: View {
    let station: SearchOsmStationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(station.name ?? L10n.string("Unknown station"))
                .font(.system(size: 16, weight: .medium))
                .lineLimit(1)

            if !station.displaySubtitle.isEmpty {
                Text(station.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let routes = station.routes, !routes.isEmpty {
                SearchFlowLayout(spacing: 4) {
                    ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                        TransitRouteBadge(
                            shortName: route.shortName,
                            longName: route.longName,
                            colorHex: route.color,
                            textColorHex: route.textColor
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct SearchFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maximumWidth = proposal.width ?? 10_000
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maximumWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: min(usedWidth, maximumWidth), height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - API models

struct SearchCypressResponse: Decodable, Sendable {
    let features: [SearchCypressFeature]?
}

struct SearchCypressFeature: Decodable, Sendable {
    let type: String?
    let geometry: SearchCypressGeometry?
    let properties: SearchCypressProperties?

    var coordinate: CLLocationCoordinate2D? {
        guard let coordinates = geometry?.coordinates, coordinates.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
    }

    fileprivate var fallbackID: String {
        "\(properties?.displayName ?? "")|\(geometry?.coordinates ?? [])"
    }
}

struct SearchCypressGeometry: Decodable, Sendable {
    let type: String?
    let coordinates: [Double]?
}

struct SearchCypressProperties: Decodable, Sendable {
    let id: String?
    let layer: String?
    let name: String?
    let names: [String: String]?
    let housenumber: String?
    let street: String?
    let postcode: String?
    let country: String?
    let region: String?
    let county: String?
    let locality: String?
    let neighbourhood: String?
    let categories: [String]?
    let confidence: Double?

    fileprivate var displayName: String {
        name ?? names?["default"] ?? L10n.string("Unknown")
    }

    fileprivate var displayTag: String {
        if let category = categories?.first {
            return category.split(separator: ":").last.map(String.init) ?? category
        }
        guard let layer, !layer.isEmpty else { return L10n.string("Place") }
        return layer.replacingOccurrences(of: "_", with: " ").capitalized
    }

    fileprivate var displaySubtitle: String {
        let parts = [housenumber, street, neighbourhood, locality ?? county, region, country]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return parts.isEmpty ? displayTag : parts.joined(separator: ", ")
    }
}

struct SearchCatenaryResponse: Decodable, Sendable {
    let stopsSection: SearchStopsSection?
    let routesSection: SearchRoutesSection?

    enum CodingKeys: String, CodingKey {
        case stopsSection = "stops_section"
        case routesSection = "routes_section"
    }
}

struct SearchStopsSection: Decodable, Sendable {
    let stops: [String: [String: SearchStopInfo]]?
    let routes: [String: [String: SearchRouteInfo]]?
    let agencies: [String: [String: SearchAgency]]?
    let ranking: [SearchStopRanking]?
}

struct SearchRoutesSection: Decodable, Sendable {
    let routes: [String: [String: SearchRouteInfo]]?
    let agencies: [String: [String: SearchAgency]]?
    let ranking: [SearchRouteRanking]?
}

struct SearchStopRanking: Decodable, Sendable {
    let gtfsID: String?
    let chateau: String?
    let score: Double?

    enum CodingKeys: String, CodingKey {
        case gtfsID = "gtfs_id"
        case chateau
        case score
    }
}

struct SearchRouteRanking: Decodable, Sendable {
    let gtfsID: String?
    let chateau: String?
    let score: Double?

    enum CodingKeys: String, CodingKey {
        case gtfsID = "gtfs_id"
        case chateau
        case score
    }
}

struct SearchStopInfo: Decodable, Sendable {
    let name: String?
    let code: String?
    let point: SearchPoint?
    let routes: [String]?
    let parentStation: String?

    enum CodingKeys: String, CodingKey {
        case name
        case code
        case point
        case routes
        case parentStation = "parent_station"
    }
}

struct SearchPoint: Decodable, Sendable {
    let x: Double
    let y: Double
}

struct SearchRouteInfo: Decodable, Sendable {
    let shortName: String?
    let longName: String?
    let color: String?
    let textColor: String?
    let agencyID: String?
    let routeID: String?
    let routeType: Int?
    let chateau: String?

    enum CodingKeys: String, CodingKey {
        case shortName = "short_name"
        case longName = "long_name"
        case color
        case textColor = "text_color"
        case agencyID = "agency_id"
        case routeID = "route_id"
        case routeType = "route_type"
        case chateau
    }

    fileprivate var displayName: String {
        if let shortName, !shortName.isEmpty { return shortName }
        if let longName, !longName.isEmpty { return longName }
        return routeID ?? L10n.string("Route")
    }
}

struct SearchAgency: Decodable, Sendable {
    let agencyName: String?

    enum CodingKeys: String, CodingKey {
        case agencyName = "agency_name"
    }
}

struct SearchOsmStationSearchResponse: Decodable, Sendable {
    let results: [SearchOsmStationResult]?
}

struct SearchOsmStationResult: Decodable, Sendable {
    let osmID: String?
    let name: String?
    let point: SearchPoint?
    let modeType: String?
    let operatorName: String?
    let network: String?
    let adminHierarchy: SearchAdminHierarchy?
    let routes: [SearchRouteInfo]?
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case osmID = "osm_id"
        case name
        case point
        case modeType = "mode_type"
        case operatorName = "operator"
        case network
        case adminHierarchy = "admin_hierarchy"
        case routes
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let integerID = try? container.decode(Int64.self, forKey: .osmID) {
            osmID = String(integerID)
        } else {
            osmID = try? container.decode(String.self, forKey: .osmID)
        }
        name = try container.decodeIfPresent(String.self, forKey: .name)
        point = try container.decodeIfPresent(SearchPoint.self, forKey: .point)
        modeType = try container.decodeIfPresent(String.self, forKey: .modeType)
        operatorName = try container.decodeIfPresent(String.self, forKey: .operatorName)
        network = try container.decodeIfPresent(String.self, forKey: .network)
        adminHierarchy = try container.decodeIfPresent(SearchAdminHierarchy.self, forKey: .adminHierarchy)
        routes = try container.decodeIfPresent([SearchRouteInfo].self, forKey: .routes)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
    }

    fileprivate var displaySubtitle: String {
        [
            adminHierarchy?.neighbourhood?.name,
            adminHierarchy?.county?.name,
            adminHierarchy?.region?.name
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    fileprivate var fallbackID: String {
        "\(name ?? "")|\(point?.x ?? 0)|\(point?.y ?? 0)"
    }
}

struct SearchAdminHierarchy: Decodable, Sendable {
    let country: SearchAdminArea?
    let neighbourhood: SearchAdminArea?
    let county: SearchAdminArea?
    let region: SearchAdminArea?
}

struct SearchAdminArea: Decodable, Sendable {
    let name: String?
}

// MARK: - Map focus helper

extension MLNCoordinateBounds {
    var catenarySearchCenter: CLLocationCoordinate2D {
        let latitude = (sw.latitude + ne.latitude) / 2
        let west = sw.longitude
        var east = ne.longitude
        if east < west {
            east += 360
        }
        var longitude = (west + east) / 2
        if longitude > 180 {
            longitude -= 360
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

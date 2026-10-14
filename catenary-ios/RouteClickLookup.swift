import Foundation

/// Parameters of Birch's asynchronous map route hit test. Only categories
/// actually visible through the user's layer switches should be included.
struct RouteClickLookup: Hashable {
    let latitude: Double
    let longitude: Double
    let zoom: Double
    let bus: Bool
    let localRail: Bool
    let intercityRail: Bool
    let other: Bool

    var hasEligibleLayers: Bool {
        zoom >= 4 && (bus || localRail || intercityRail || other)
    }
}

private struct ServerRouteHit: Decodable {
    let chateau: String
    let route_id: String
    let colour: String
    let name: String
    let route_type: Int

    var selectionOption: MapSelectionOption {
        MapSelectionOption(data: .route(
            chateauID: chateau,
            routeID: route_id,
            colour: colour.replacingOccurrences(of: "#", with: ""),
            name: name,
            routeType: route_type
        ))
    }
}

enum RouteClickAPI {
    static func fetch(_ lookup: RouteClickLookup) async throws -> [MapSelectionOption] {
        guard lookup.hasEligibleLayers else { return [] }
        var components = URLComponents(string: "https://birch.catenarymaps.org/routes_at_point")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(lookup.latitude)),
            URLQueryItem(name: "longitude", value: String(lookup.longitude)),
            URLQueryItem(name: "zoom", value: String(lookup.zoom)),
            URLQueryItem(name: "bus", value: String(lookup.bus)),
            URLQueryItem(name: "local_rail", value: String(lookup.localRail)),
            URLQueryItem(name: "intercity_rail", value: String(lookup.intercityRail)),
            URLQueryItem(name: "other", value: String(lookup.other))
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([ServerRouteHit].self, from: data)
            .map(\.selectionOption)
    }
}

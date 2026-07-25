import Foundation

enum StopFetchResult: Sendable {
    case departures(DeparturesAtStopResponse)
    case redirect(osmStationID: Int64)
}

actor StopAPIClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func fetchDepartures(
        source: StopScreenSource,
        start: Int64,
        end: Int64
    ) async throws -> StopFetchResult {
        let url = try departuresURL(source: source, start: start, end: end)
        let data = try await data(from: url)

        if let redirect = try? decoder.decode(OSMStationRedirectResponse.self, from: data) {
            return .redirect(osmStationID: redirect.redirectToOsmStationId)
        }

        return .departures(try decoder.decode(DeparturesAtStopResponse.self, from: data))
    }

    func lookupOSMStation(chateauID: String, stopID: String) async throws -> OSMStationLookupResponse {
        var components = URLComponents(string: "https://birch.catenarymaps.org/osm_station_lookup")!
        components.queryItems = [
            URLQueryItem(name: "chateau_id", value: chateauID),
            URLQueryItem(name: "gtfs_stop_id", value: stopID)
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        return try decoder.decode(OSMStationLookupResponse.self, from: await data(from: url))
    }

    private func departuresURL(
        source: StopScreenSource,
        start: Int64,
        end: Int64
    ) throws -> URL {
        var components: URLComponents

        switch source {
        case let .stop(chateauID, stopID):
            components = URLComponents(
                string: "https://birchdeparturesfromstop.catenarymaps.org/departures_at_stop"
            )!
            components.queryItems = [
                URLQueryItem(name: "chateau_id", value: chateauID),
                URLQueryItem(name: "stop_id", value: stopID),
                URLQueryItem(name: "greater_than_time", value: String(start)),
                URLQueryItem(name: "less_than_time", value: String(end)),
                URLQueryItem(name: "include_shapes", value: "false")
            ]

        case let .osmStation(id):
            components = URLComponents(
                string: "https://birch.catenarymaps.org/departures_at_osm_station"
            )!
            components.queryItems = [
                URLQueryItem(name: "osm_station_id", value: id),
                URLQueryItem(name: "greater_than_time", value: String(start)),
                URLQueryItem(name: "less_than_time", value: String(end)),
                URLQueryItem(name: "include_shapes", value: "false")
            ]
        }

        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

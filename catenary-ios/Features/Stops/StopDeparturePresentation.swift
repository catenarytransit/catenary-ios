import CoreLocation
import Foundation

enum StopDepartureLayout: Int, Sendable {
    case regular
    case eurostyle
    case swiss
}

enum StopDeparturePresentation {
    private struct FeatureCollection: Decodable {
        let features: [Feature]
    }

    private struct Feature: Decodable {
        let geometry: Geometry?
    }

    private struct Geometry: Decodable {
        private enum CodingKeys: String, CodingKey {
            case type
            case coordinates
        }

        let polygons: [[[[Double]]]]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "Polygon":
                polygons = [try container.decode([[[Double]]].self, forKey: .coordinates)]
            case "MultiPolygon":
                polygons = try container.decode([[[[Double]]]].self, forKey: .coordinates)
            default:
                polygons = []
            }
        }
    }

    private struct Polygon {
        let rings: [[[Double]]]
        let minimumLongitude: Double
        let maximumLongitude: Double
        let minimumLatitude: Double
        let maximumLatitude: Double

        init(rings: [[[Double]]]) {
            self.rings = rings
            let positions = rings.flatMap { $0 }.filter { $0.count >= 2 }
            minimumLongitude = positions.map { $0[0] }.min() ?? 0
            maximumLongitude = positions.map { $0[0] }.max() ?? 0
            minimumLatitude = positions.map { $0[1] }.min() ?? 0
            maximumLatitude = positions.map { $0[1] }.max() ?? 0
        }

        func contains(longitude: Double, latitude: Double) -> Bool {
            guard longitude >= minimumLongitude,
                  longitude <= maximumLongitude,
                  latitude >= minimumLatitude,
                  latitude <= maximumLatitude,
                  let exterior = rings.first,
                  Self.ringContains(exterior, longitude: longitude, latitude: latitude) else {
                return false
            }

            return !rings.dropFirst().contains {
                Self.ringContains($0, longitude: longitude, latitude: latitude)
            }
        }

        private static func ringContains(
            _ ring: [[Double]],
            longitude: Double,
            latitude: Double
        ) -> Bool {
            guard ring.count >= 3 else { return false }

            var isInside = false
            var previousIndex = ring.count - 1

            for currentIndex in ring.indices {
                let current = ring[currentIndex]
                let previous = ring[previousIndex]
                guard current.count >= 2, previous.count >= 2 else {
                    previousIndex = currentIndex
                    continue
                }

                let currentX = current[0]
                let currentY = current[1]
                let previousX = previous[0]
                let previousY = previous[1]

                if pointIsOnSegment(
                    longitude: longitude,
                    latitude: latitude,
                    x1: previousX,
                    y1: previousY,
                    x2: currentX,
                    y2: currentY
                ) {
                    return true
                }

                let crossesLatitude = (currentY > latitude) != (previousY > latitude)
                if crossesLatitude {
                    let longitudeAtIntersection = previousX
                        + (currentX - previousX) * (latitude - previousY) / (currentY - previousY)
                    if longitude < longitudeAtIntersection {
                        isInside.toggle()
                    }
                }

                previousIndex = currentIndex
            }

            return isInside
        }

        private static func pointIsOnSegment(
            longitude: Double,
            latitude: Double,
            x1: Double,
            y1: Double,
            x2: Double,
            y2: Double
        ) -> Bool {
            let epsilon = 1e-10
            let crossProduct = (latitude - y1) * (x2 - x1) - (longitude - x1) * (y2 - y1)
            guard abs(crossProduct) <= epsilon else { return false }

            let dotProduct = (longitude - x1) * (longitude - x2)
                + (latitude - y1) * (latitude - y2)
            return dotProduct <= epsilon
        }
    }

    private struct FernverkehrEntry: Decodable {
        let displayName: String?

        private enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    private static let dbFernverkehrAgencyIDs: Set<String> = ["12681", "13557", "10918"]
    private static let layoutCache = NSCache<NSString, NSNumber>()

    private static let eurostylePolygons = loadPolygons(resource: "eurostyle-ui-zone")
    private static let switzerlandPolygons = loadPolygons(resource: "switzerland")

    private static let fernverkehrDisplayNames: [String: String] = {
        guard let url = resourceURL(
            resource: "fernverkehr_2026_train_lookup",
            extension: "json"
        ),
        let data = try? Data(contentsOf: url),
        let entries = try? JSONDecoder().decode([String: [FernverkehrEntry]].self, from: data) else {
            return [:]
        }

        return entries.reduce(into: [:]) { result, item in
            if let displayName = item.value.first?.displayName, !displayName.isEmpty {
                result[item.key] = displayName
            }
        }
    }()

    static func layout(for coordinate: CLLocationCoordinate2D?) -> StopDepartureLayout {
        guard let coordinate else { return .regular }

        let cacheKey = String(
            format: "%.5f|%.5f",
            coordinate.latitude,
            coordinate.longitude
        ) as NSString
        if let cached = layoutCache.object(forKey: cacheKey),
           let layout = StopDepartureLayout(rawValue: cached.intValue) {
            return layout
        }

        let layout: StopDepartureLayout
        if contains(coordinate, polygons: switzerlandPolygons) {
            layout = .swiss
        } else if contains(coordinate, polygons: eurostylePolygons) {
            layout = .eurostyle
        } else {
            layout = .regular
        }

        layoutCache.setObject(NSNumber(value: layout.rawValue), forKey: cacheKey)
        return layout
    }

    static func dbFernverkehrDisplayName(
        event: StopEvent,
        routeInfo: StopRouteInfo?
    ) -> String? {
        guard event.chateau == "deutschland",
              let agencyID = routeInfo?.agencyId,
              dbFernverkehrAgencyIDs.contains(agencyID),
              let rawTrainNumber = event.tripShortName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTrainNumber.isEmpty else {
            return nil
        }

        let stripped = rawTrainNumber.drop(while: { $0 == "0" })
        let lookupKey = stripped.isEmpty ? "0" : String(stripped)
        return fernverkehrDisplayNames[lookupKey]
    }

    static func trainCategory(
        chateauID: String?,
        routeShortName: String?,
        event: StopEvent,
        routeInfo: StopRouteInfo?
    ) -> String {
        StopTrainCategoryClassifier.category(
            chateauID: chateauID,
            shortName: dbFernverkehrDisplayName(event: event, routeInfo: routeInfo)
                ?? routeShortName
        )
    }

    private static func contains(
        _ coordinate: CLLocationCoordinate2D,
        polygons: [Polygon]
    ) -> Bool {
        polygons.contains {
            $0.contains(longitude: coordinate.longitude, latitude: coordinate.latitude)
        }
    }

    private static func loadPolygons(resource: String) -> [Polygon] {
        guard let url = resourceURL(resource: resource, extension: "geojson"),
              let data = try? Data(contentsOf: url),
              let collection = try? JSONDecoder().decode(FeatureCollection.self, from: data) else {
            return []
        }

        return collection.features
            .compactMap(\.geometry)
            .flatMap(\.polygons)
            .map { Polygon(rings: $0) }
    }

    private static func resourceURL(resource: String, extension fileExtension: String) -> URL? {
        Bundle.main.url(
            forResource: resource,
            withExtension: fileExtension,
            subdirectory: "Resources/TransitStyle"
        ) ?? Bundle.main.url(forResource: resource, withExtension: fileExtension)
    }
}

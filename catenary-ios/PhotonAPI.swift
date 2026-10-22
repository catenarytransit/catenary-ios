import Foundation

/// Photon returns GeoJSON, with OSM identities stored separately from its
/// broad search result layer. Keep this model independent of the search UI.
enum PhotonAPI {
    static func searchURL(
        query: String,
        latitude: Double,
        longitude: Double,
        zoom: Double,
        locationBiasScale: Double = 0.1
    ) -> URL? {
        var components = URLComponents(string: "https://photon.komoot.io/api/")
        var parameters = [URLQueryItem(name: "q", value: query)]

        if latitude.isFinite, longitude.isFinite,
           (-90...90).contains(latitude), (-180...180).contains(longitude) {
            parameters.append(URLQueryItem(name: "lat", value: String(latitude)))
            parameters.append(URLQueryItem(name: "lon", value: String(longitude)))
        }

        let focusedZoom = zoom.isFinite ? Int(min(max(zoom.rounded(), 0), 20)) : 12
        parameters.append(URLQueryItem(name: "zoom", value: String(focusedZoom)))

        let scale = locationBiasScale.isFinite
            ? min(max(locationBiasScale, 0), 1) : 0.1
        parameters.append(URLQueryItem(name: "location_bias_scale", value: String(scale)))
        components?.queryItems = parameters
        return components?.url
    }
}

struct PhotonResponse: Decodable, Sendable {
    let type: String
    let features: [PhotonFeature]
}

struct PhotonFeature: Decodable, Sendable {
    let type: String
    let properties: PhotonProperties
    let geometry: PhotonGeometry

    var coordinate: (latitude: Double, longitude: Double)? {
        guard type == "Feature", geometry.type == "Point",
              geometry.coordinates.count == 2 else { return nil }
        let longitude = geometry.coordinates[0]
        let latitude = geometry.coordinates[1]
        guard longitude.isFinite, latitude.isFinite,
              (-180...180).contains(longitude), (-90...90).contains(latitude) else {
            return nil
        }
        return (latitude, longitude)
    }

    var osmReference: PhotonOSMReference? {
        guard let osmType = properties.osmType,
              let osmID = properties.osmID, osmID > 0 else { return nil }
        let osmClass: String
        switch osmType.uppercased() {
        case "N": osmClass = "node"
        case "W": osmClass = "way"
        case "R": osmClass = "relation"
        default: return nil
        }
        return PhotonOSMReference(osmClass: osmClass, osmID: String(osmID))
    }
}

struct PhotonOSMReference: Sendable, Equatable {
    let osmClass: String
    let osmID: String
}

struct PhotonGeometry: Decodable, Sendable {
    let type: String
    let coordinates: [Double]
}

struct PhotonProperties: Decodable, Sendable {
    let osmType: String?
    let osmID: Int64?
    let osmKey: String?
    let osmValue: String?
    let type: String?
    let name: String?
    let housenumber: String?
    let street: String?
    let postcode: String?
    let country: String?
    let state: String?
    let county: String?
    let city: String?
    let locality: String?
    let district: String?

    enum CodingKeys: String, CodingKey {
        case osmType = "osm_type"
        case osmID = "osm_id"
        case osmKey = "osm_key"
        case osmValue = "osm_value"
        case type, name, housenumber, street, postcode, country, state
        case county, city, locality, district
    }
}

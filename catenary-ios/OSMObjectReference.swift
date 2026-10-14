import Foundation

/// A real OSM object ID and its type. Never send the OpenMapTiles synthetic
/// vector-feature identifier to the OSM API.
struct OSMObjectReference: Hashable {
    let osmClass: String
    let osmID: String

    init?(osmClass: String, osmID: String) {
        guard ["node", "way", "relation"].contains(osmClass),
              let value = UInt64(osmID), value > 0 else { return nil }
        self.osmClass = osmClass
        self.osmID = String(value)
    }

    /// The deployed Catenary OpenMapTiles POI source uses
    /// 10 * osmID + (1: node, 2: way, 3: relation).
    /// Convert directly from a decimal string / NSNumber, never via Double:
    /// OSM identifiers can exceed 2^53 in their encoded representation.
    static func fromPOIFeatureIdentifier(_ identifier: Any?) -> Self? {
        let raw: String
        switch identifier {
        case let value as NSNumber: raw = value.stringValue
        case let value as String: raw = value
        default: return nil
        }
        guard let encoded = UInt64(raw), encoded >= 11 else { return nil }
        let type: String
        switch encoded % 10 {
        case 1: type = "node"
        case 2: type = "way"
        case 3: type = "relation"
        default: return nil
        }
        return Self(osmClass: type, osmID: String(encoded / 10))
    }

    /// Cypress search IDs are 'node:123', 'way:123', 'relation:123'.
    /// Accept the OSM URL path form as well; reject untyped numerical IDs.
    static func fromCypressIdentifier(_ identifier: String?) -> Self? {
        guard let identifier else { return nil }
        let separator: Character = identifier.contains(":") ? ":" : "/"
        let parts = identifier.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return Self(osmClass: String(parts[0]), osmID: String(parts[1]))
    }
}

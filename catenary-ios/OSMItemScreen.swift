import CoreLocation
import Foundation
import SwiftUI

private struct OSMAPIResponse: Decodable {
    let elements: [OSMAPIElement]
}

private struct OSMAPICoordinate: Decodable {
    let lat: Double
    let lon: Double
}

private struct OSMAPIElement: Decodable {
    let type: String
    let id: UInt64
    let tags: [String: String]?
    let lat: Double?
    let lon: Double?
    let center: OSMAPICoordinate?
}

/// Translations live in OSMItem.xcstrings, taken from the Android OSM strings.
private enum OSMText {
    static func value(_ key: String, fallback: String) -> String {
        let resource = LocalizedStringResource(
            String.LocalizationValue(key),
            table: "OSMItem",
            locale: .autoupdatingCurrent,
            bundle: .main
        )
        let translated = String(localized: resource)
        return translated == key ? fallback : translated
    }
}

/// Map and Cypress search result OSM details. Navigation chrome is supplied by
/// BottomDrawer, just like the GTFS stop / OSM station destinations.
struct OSMItemScreen: View {
    let osmID: String
    let osmClass: String
    let osmType: String?
    let previewName: String?
    let latitude: Double?
    let longitude: Double?

    @EnvironmentObject private var navigator: viewObject
    @Environment(\.openURL) private var openURL
    @State private var element: OSMAPIElement?
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0
    @State private var namesExpanded = false
    @State private var tagsExpanded = false

    private var reference: OSMObjectReference? {
        OSMObjectReference(osmClass: osmClass, osmID: osmID)
    }

    private var tags: [String: String] { element?.tags ?? [:] }

    private var objectType: String {
        switch osmClass {
        case "node": return OSMText.value("osm_node", fallback: "Node")
        case "way": return OSMText.value("osm_way", fallback: "Way")
        case "relation": return OSMText.value("osm_relation", fallback: "Relation")
        default: return OSMText.value("osm_feature", fallback: "OpenStreetMap feature")
        }
    }

    private var title: String {
        let language = Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"
        return tags["name:\(language)"]?.nilIfEmpty
            ?? tags["name"]?.nilIfEmpty
            ?? previewName?.nilIfEmpty
            ?? "\(objectType) \(osmID)"
    }

    private var category: String {
        let raw = ["amenity", "shop", "tourism", "leisure", "office", "craft"]
            .compactMap { tags[$0]?.nilIfEmpty }.first ?? osmType ?? objectType
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var address: String? {
        let street = [tags["addr:street"], tags["addr:housenumber"]]
            .compactMap { $0?.nilIfEmpty }.joined(separator: " ")
        return [street.nilIfEmpty, tags["addr:postcode"], tags["addr:city"],
                tags["addr:state"], tags["addr:country"]]
            .compactMap { $0?.nilIfEmpty }.joined(separator: ", ").nilIfEmpty
    }

    private var nearbyCoordinate: CLLocationCoordinate2D? {
        let candidates: [(Double?, Double?)] = [
            (latitude, longitude), (element?.lat, element?.lon),
            (element?.center?.lat, element?.center?.lon)
        ]
        for (lat, lon) in candidates {
            if let lat, let lon, lat.isFinite, lon.isFinite,
               (-90...90).contains(lat), (-180...180).contains(lon) {
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
        return nil
    }

    private var alternateNames: [(String, String)] {
        tags.filter { $0.key.hasPrefix("name:") && !$0.value.isEmpty && $0.value != title }
            .map { (String($0.key.dropFirst(5)), $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    private var website: URL? {
        guard let raw = (tags["website"] ?? tags["contact:website"])?.nilIfEmpty else { return nil }
        let formatted = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: formatted),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host?.isEmpty == false else { return nil }
        return url
    }

    private var phone: String? {
        (tags["phone"] ?? tags["contact:phone"])?.nilIfEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(category)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let address {
                    Text(address)
                        .font(.subheadline)
                }

                Button {
                    guard let nearbyCoordinate else { return }
                    navigator.push(.nearbyDepartures(
                        chateauID: "",
                        latitude: nearbyCoordinate.latitude,
                        longitude: nearbyCoordinate.longitude
                    ))
                } label: {
                    Label(
                        OSMText.value("osm_nearby", fallback: "Show nearby departures from here"),
                        systemImage: "tram.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(nearbyCoordinate == nil)

                if nearbyCoordinate == nil {
                    Text(OSMText.value("osm_nearby_unavailable", fallback: "Location unavailable for nearby departures"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if loading {
                    HStack {
                        ProgressView()
                        Text(OSMText.value("osm_loading", fallback: "Loading OpenStreetMap details…"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error {
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button(OSMText.value("osm_retry", fallback: "Retry")) { retry += 1 }
                        .buttonStyle(.borderedProminent)
                }

                if !alternateNames.isEmpty {
                    DisclosureGroup(isExpanded: $namesExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(alternateNames.indices, id: \.self) { index in
                                let item = alternateNames[index]
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.0).font(.caption).foregroundStyle(.secondary)
                                    Text(item.1).textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.top, 10)
                    } label: {
                        Label(
                            OSMText.value("osm_other_names", fallback: "Other names (%1$d)")
                                .replacingOccurrences(of: "%1$d", with: String(alternateNames.count)),
                            systemImage: "character.bubble"
                        )
                    }
                    .osmInformationSurface()
                }

                if let website {
                    Button { openURL(website) } label: {
                        OSMContactRow(
                            icon: "globe",
                            label: OSMText.value("osm_website", fallback: "Website"),
                            value: website.host?.replacingOccurrences(of: "www.", with: "") ?? website.absoluteString
                        )
                    }
                    .buttonStyle(.plain)
                    .osmInformationSurface()
                }
                if let phone {
                    let first = phone.components(separatedBy: ";").first ?? phone
                    let dialable = first.filter { "0123456789+*#".contains($0) }
                    Button {
                        if let url = URL(string: "tel:\(dialable)") { openURL(url) }
                    } label: {
                        OSMContactRow(
                            icon: "phone",
                            label: OSMText.value("osm_phone", fallback: "Phone number"),
                            value: phone
                        )
                    }
                    .disabled(dialable.isEmpty)
                    .buttonStyle(.plain)
                    .osmInformationSurface()
                }
                if let hours = tags["opening_hours"]?.nilIfEmpty {
                    OSMContactRow(
                        icon: "clock",
                        label: OSMText.value("osm_hours", fallback: "Opening hours"),
                        value: hours
                    )
                    .osmInformationSurface()
                }

                let amenities: [(String, String)] = [
                    ("wheelchair", "osm_wheelchair"),
                    ("toilets", "osm_toilets"),
                    ("toilets:wheelchair", "osm_accessible_toilets"),
                    ("indoor_seating", "osm_indoor_seating"),
                    ("outdoor_seating", "osm_outdoor_seating"),
                    ("takeaway", "osm_takeaway"),
                    ("internet_access", "osm_internet_access")
                ]
                let presentAmenities = amenities.compactMap { key, label -> (String, String)? in
                    guard let value = tags[key]?.nilIfEmpty else { return nil }
                    return (OSMText.value(label, fallback: key.replacingOccurrences(of: "_", with: " ").capitalized), value)
                }
                if !presentAmenities.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(OSMText.value("osm_amenities", fallback: "Amenities & accessibility"))
                            .font(.headline)
                        ForEach(presentAmenities.indices, id: \.self) { index in
                            let item = presentAmenities[index]
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.0)
                                Spacer()
                                Text(localizedTagValue(item.1)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .osmInformationSurface()
                }

                if !tags.isEmpty {
                    DisclosureGroup(isExpanded: $tagsExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(tags.keys.sorted(), id: \.self) { key in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(key).font(.caption).foregroundStyle(.secondary)
                                    Text(tags[key] ?? "").textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Label(
                            OSMText.value("osm_details", fallback: "Details"),
                            systemImage: "list.bullet.rectangle"
                        )
                    }
                    .osmInformationSurface()
                }
                if let reference,
                   let url = URL(string: "https://www.openstreetmap.org/\(reference.osmClass)/\(reference.osmID)") {
                    Link(destination: url) {
                        Label(OSMText.value("osm_view_osm", fallback: "View on OpenStreetMap"), systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 56)
        }
        .task(id: "\(osmClass)/\(osmID)/\(retry)") { await load() }
        .onAppear(perform: recordVisit)
        .onDisappear { navigator.clearSelectedStopContext(id: contextID) }
    }

    private var contextID: String { "osm-item|\(osmClass)|\(osmID)" }

    private func recordVisit() {
        SearchHistoryStore.record(SearchHistoryItem(
            id: contextID,
            kind: .osmItem,
            title: previewName ?? "\(objectType) \(osmID)",
            subtitle: osmType,
            osmStationID: osmID,
            osmClass: osmClass,
            osmType: osmType,
            latitude: latitude,
            longitude: longitude
        ))
        updateMapPin()
    }

    private func updateMapPin() {
        guard let coordinate = nearbyCoordinate else { return }
        navigator.setSelectedStopContext(SelectedStopMapContext(
            id: contextID, name: title,
            latitude: coordinate.latitude, longitude: coordinate.longitude
        ))
    }

    private func localizedTagValue(_ value: String) -> String {
        let key: String
        switch value.lowercased() {
        case "yes", "no", "limited", "designated", "only": key = "osm_\(value.lowercased())"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return OSMText.value(key, fallback: value.capitalized)
    }

    private func load() async {
        loading = true
        error = nil
        element = nil
        defer { loading = false }
        guard let reference,
              let url = URL(string: "https://www.openstreetmap.org/api/0.6/\(reference.osmClass)/\(reference.osmID).json") else {
            error = OSMText.value("osm_invalid_id", fallback: "This search result has no public OSM object identifier.")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let items = try JSONDecoder().decode(OSMAPIResponse.self, from: data).elements
            guard let value = items.first(where: {
                $0.type == reference.osmClass && String($0.id) == reference.osmID
            }) else {
                error = OSMText.value("osm_object_missing", fallback: "OpenStreetMap did not return this object.")
                return
            }
            guard !Task.isCancelled else { return }
            element = value
            updateMapPin()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.error = OSMText.value("osm_load_failed", fallback: "Could not load OpenStreetMap details.")
        }
    }
}

private struct OSMContactRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).foregroundStyle(.primary).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private extension View {
    func osmInformationSurface() -> some View {
        padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
    }
}

private extension String {
    var nilIfEmpty: String? {
        let stripped = trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }
}

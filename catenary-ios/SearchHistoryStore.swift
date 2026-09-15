import Foundation

struct SearchHistoryItem: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case cypress
        case stop
        case route
        case osmStation
    }

    let id: String
    let kind: Kind
    var title: String
    var subtitle: String?
    var chateauID: String?
    var gtfsID: String?
    var osmStationID: String?
    var modeType: String?
    var latitude: Double?
    var longitude: Double?

    init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        chateauID: String? = nil,
        gtfsID: String? = nil,
        osmStationID: String? = nil,
        modeType: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.chateauID = chateauID
        self.gtfsID = gtfsID
        self.osmStationID = osmStationID
        self.modeType = modeType
        self.latitude = latitude
        self.longitude = longitude
    }

    var systemImage: String {
        switch kind {
        case .cypress:
            return "mappin.and.ellipse"
        case .stop:
            return "mappin.circle.fill"
        case .route:
            return "point.topleft.down.to.point.bottomright.curvepath"
        case .osmStation:
            return "building.2.fill"
        }
    }
}

enum SearchHistoryStore {
    private struct Entry: Codable {
        var item: SearchHistoryItem
        var visits: [TimeInterval]
    }

    private static let storageKey = "catenary.search.history.v1"
    private static let maximumItems = 100
    private static let duplicateWindow: TimeInterval = 30
    private static let recencyDecay: TimeInterval = 14 * 24 * 60 * 60

    static func record(
        _ item: SearchHistoryItem,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        var entries = loadEntries()

        if let index = entries.firstIndex(where: { $0.item.id == item.id }) {
            if let latestVisit = entries[index].visits.max(),
               now - latestVisit < duplicateWindow {
                return
            }
            entries[index].item = item
            entries[index].visits.append(now)
        } else {
            entries.append(Entry(item: item, visits: [now]))
        }

        entries.sort {
            ($0.visits.max() ?? 0) > ($1.visits.max() ?? 0)
        }
        if entries.count > maximumItems {
            entries.removeSubrange(maximumItems...)
        }

        save(entries)
    }

    static func topItems(
        limit: Int = 10,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [SearchHistoryItem] {
        guard limit > 0 else { return [] }

        return loadEntries()
            .compactMap { entry -> (item: SearchHistoryItem, score: Double)? in
                guard let latestVisit = entry.visits.max(), !entry.visits.isEmpty else {
                    return nil
                }
                let frequencyScore = log(exp(1.0) + Double(entry.visits.count))
                let age = max(0, now - latestVisit)
                let recencyScore = exp(-age / recencyDecay)
                return (entry.item, frequencyScore * recencyScore)
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.item)
    }

    private static func loadEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func save(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

import Foundation

/// A visible badge can represent several route IDs, but never crosses feed boundaries.
struct DepartureRouteFilterKey: Hashable {
    let chateauID: String
    let name: String
    let color: String
}

struct DepartureRouteFilter: Identifiable, Equatable {
    let key: DepartureRouteFilterKey
    var routeIDs: Set<String>
    var id: DepartureRouteFilterKey { key }
}

struct DepartureRouteDefinition {
    let chateauID: String
    let routeID: String
    let shortName: String?
    let longName: String?
    let color: String?
}

enum DepartureRouteFilters {
    static func badges(for routes: [DepartureRouteDefinition]) -> [DepartureRouteFilter] {
        var grouped: [DepartureRouteFilterKey: Set<String>] = [:]
        for route in routes {
            let name = [route.shortName, route.longName].compactMap { $0 }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? route.routeID
            let color = (route.color ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = DepartureRouteFilterKey(chateauID: route.chateauID, name: name,
                color: (color.hasPrefix("#") ? String(color.dropFirst()) : color).uppercased())
            grouped[key, default: []].insert(route.routeID)
        }
        return grouped.map { DepartureRouteFilter(key: $0.key, routeIDs: $0.value) }.sorted {
            if $0.key.name != $1.key.name { return namePrecedes($0.key.name, $1.key.name) }
            if $0.key.chateauID != $1.key.chateauID { return $0.key.chateauID < $1.key.chateauID }
            return $0.key.color < $1.key.color
        }
    }

    static func isEnabled(badgeCount: Int, isRail: Bool, hasCategoryFilters: Bool,
                          hasNationalRail: Bool) -> Bool {
        badgeCount > 1 && !(isRail && (hasCategoryFilters || hasNationalRail))
    }

    static func matches(chateauID: String, routeID: String,
                        selected: Set<DepartureRouteFilterKey>, badges: [DepartureRouteFilter]) -> Bool {
        selected.isEmpty || badges.contains {
            selected.contains($0.key) && $0.key.chateauID == chateauID && $0.routeIDs.contains(routeID)
        }
    }

    /// Match Compose's digit-run ordering without converting arbitrarily long IDs to integers.
    static func namePrecedes(_ left: String, _ right: String) -> Bool {
        func runs(_ value: String) -> [String] {
            var result: [String] = []
            for character in value {
                if let last = result.last, last.last!.isASCIIDigit == character.isASCIIDigit {
                    result[result.count - 1].append(character)
                } else {
                    result.append(String(character))
                }
            }
            return result
        }
        let a = runs(left), b = runs(right)
        for (x, y) in zip(a, b) {
            let xn = x.first!.isASCIIDigit, yn = y.first!.isASCIIDigit
            if xn && yn {
                let nx = x.drop(while: { $0 == "0" }), ny = y.drop(while: { $0 == "0" })
                if nx.count != ny.count { return nx.count < ny.count }
                if nx != ny { return nx.lexicographicallyPrecedes(ny) }
            } else if xn != yn {
                return xn
            } else if x.lowercased() != y.lowercased() {
                return x.lowercased() < y.lowercased()
            }
        }
        if a.count != b.count { return a.count < b.count }
        return left < right
    }
}

private extension Character {
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}

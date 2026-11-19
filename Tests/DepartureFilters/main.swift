import Foundation

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
}
func route(_ id: String, _ name: String?, feed: String = "local", color: String? = "#ff0000",
           longName: String? = nil) -> DepartureRouteDefinition {
    DepartureRouteDefinition(chateauID: feed, routeID: id, shortName: name, longName: longName, color: color)
}
let badges = DepartureRouteFilters.badges(for: [
    route("outbound", "2"), route("inbound", "2", color: "FF0000"),
    route("ten", "10"), route("other-feed", "2", feed: "other"),
    route("blue", "2", color: "0000ff"), route("fallback", " ", longName: "Airport"),
    route("unnamed", nil)
])
expect(badges.count == 6, "Identical badges merge; feeds and colors remain separate")
let red = badges.first { $0.key.chateauID == "local" && $0.key.name == "2" && $0.key.color == "FF0000" }!
expect(red.routeIDs == ["outbound", "inbound"], "Both direction IDs share one selection")
expect(badges.map(\.key.name) == ["2", "2", "2", "10", "Airport", "unnamed"], "Natural ordering and name fallbacks")
expect(DepartureRouteFilters.matches(chateauID: "local", routeID: "ten", selected: [], badges: badges), "Empty selection shows all")
expect(DepartureRouteFilters.matches(chateauID: "local", routeID: "inbound", selected: [red.key], badges: badges), "Selected badge includes all its route IDs")
expect(!DepartureRouteFilters.matches(chateauID: "other", routeID: "other-feed", selected: [red.key], badges: badges), "Feed isolation")
expect(!DepartureRouteFilters.matches(chateauID: "local", routeID: "blue", selected: [red.key], badges: badges), "Color isolation")
let ten = badges.first { $0.key.name == "10" }!
expect(DepartureRouteFilters.matches(chateauID: "local", routeID: "ten", selected: [red.key, ten.key], badges: badges), "Multi-selection is a union")
expect(Set([red.key, ten.key]).intersection(Set([red.key])) == [red.key], "Refresh prunes only missing badges")
for count in [0, 1] {
    expect(!DepartureRouteFilters.isEnabled(badgeCount: count, isRail: false, hasCategoryFilters: false, hasNationalRail: false), "Single badge does not offer a filter")
}
expect(DepartureRouteFilters.isEnabled(badgeCount: 2, isRail: true, hasCategoryFilters: false, hasNationalRail: false), "Ordinary rail supports route filters")
expect(!DepartureRouteFilters.isEnabled(badgeCount: 2, isRail: true, hasCategoryFilters: true, hasNationalRail: false), "Existing Swiss/German/IDF category controls exclude route row")
expect(!DepartureRouteFilters.isEnabled(badgeCount: 2, isRail: true, hasCategoryFilters: false, hasNationalRail: true), "National Rail exclusion")
expect(DepartureRouteFilters.isEnabled(badgeCount: 2, isRail: false, hasCategoryFilters: true, hasNationalRail: true), "Buses and metros at rail stations still support routes")
let names = ["10", "2", "02", "1A", "A10", "A2", "0", "00", "a2", String(repeating: "9", count: 50)]
let ordered = names.sorted(by: DepartureRouteFilters.namePrecedes)
expect(ordered.first == "0" && ordered.firstIndex(of: "2")! < ordered.firstIndex(of: "10")!, "Zero and numeric order")
expect(ordered.firstIndex(of: "A2")! < ordered.firstIndex(of: "A10")!, "Embedded numeric order")
for a in names {
    expect(!DepartureRouteFilters.namePrecedes(a, a), "Strict ordering")
    for b in names where DepartureRouteFilters.namePrecedes(a, b) {
        expect(!DepartureRouteFilters.namePrecedes(b, a), "Antisymmetry")
        for c in names where DepartureRouteFilters.namePrecedes(b, c) {
            expect(DepartureRouteFilters.namePrecedes(a, c), "Transitivity")
        }
    }
}
print("Departure route grouping, selection, exclusions and ordering passed")

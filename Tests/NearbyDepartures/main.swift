import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

func frame(_ phase: String, _ payload: String, id: String = "request", complete: Bool? = nil) throws -> NearbyDepartureMessage {
    let finished = complete ?? (phase != "priority")
    let json = """
    {"type":"nearby_departures","request_id":"\(id)","phase":"\(phase)","complete":\(finished),"data":\(payload)}
    """
    return try decoder.decode(NearbyDepartureMessage.self, from: Data(json.utf8))
}

func payload(local: String = "[]", stations: String = "[]", routes: String = "{}", stops: String = "{}") -> String {
    """
    {"long_distance":\(stations),"local":\(local),"routes":\(routes),"stops":\(stops)}
    """
}

func departure(_ time: Int, realtime: Int? = nil, date: String = "2026-11-25", arrival: Int? = nil) -> String {
    """
    {"trip_id":"loop","stop_id":"s","service_date":"\(date)","departure_schedule":\(time),"departure_realtime":\(realtime.map(String.init) ?? "null"),"arrival_schedule":\(arrival.map(String.init) ?? "null")}
    """
}

func route(_ feed: String = "city", headsigns: String, distance: Int = 50) -> String {
    """
    {"chateau_id":"\(feed)","route_id":"1","route_type":3,"closest_distance":\(distance),"headsigns":\(headsigns)}
    """
}

func stationDeparture(_ feed: String, realtime: Int? = nil) -> String {
    """
    {"chateau_id":"\(feed)","route_id":"1","trip_id":"t","stop_id":"s","service_date":"2026-11-25","scheduled_departure":100,"realtime_departure":\(realtime.map(String.init) ?? "null"),"headsign":"Central"}
    """
}

func station(_ departures: String, lat: Double) -> String {
    """
    {"station_name":"Central","osm_station_id":123,"distance_m":200,"departures":\(departures),"lat":\(lat),"lon":2,"timezone":"UTC"}
    """
}

func isIgnored(_ value: NearbyDepartureFrameResult) -> Bool {
    if case .ignored = value { return true }
    return false
}

func completed(_ value: NearbyDepartureFrameResult) -> NearbyAPIResponse {
    guard case .complete(let response) = value else { fatalError("Expected completion") }
    return response
}

func expectError(_ operation: () throws -> Void) {
    do {
        try operation()
        fatalError("Expected error")
    } catch {}
}

let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
let north = route(headsigns: "{\"North\":[\(departure(100, arrival: 90))]}")
let more = route(headsigns: "{\"North\":[\(departure(100, realtime: 110, arrival: 90)),\(departure(200)),\(departure(100, date: "2026-11-26", arrival: 90)),\(departure(100, arrival: 95))],\"South\":[\(departure(300))]}", distance: 40)
let other = route("other", headsigns: "{\"North\":[\(departure(100))]}")
let first = try frame("priority", payload(
    local: "[\(north)]", stations: "[\(station("[\(stationDeparture("city"))]", lat: 1))]",
    routes: "{\"city\":{\"1\":{\"route_type\":3}}}",
    stops: "{\"city\":{\"s\":{\"name\":\"Old\",\"lat\":1,\"lon\":2}}}"
))
let remaining = try frame("remaining", payload(
    local: "[\(more),\(other)]",
    stations: "[\(station("[\(stationDeparture("city", realtime: 110)),\(stationDeparture("other"))]", lat: 1.001))]",
    routes: "{\"city\":{\"2\":{\"route_type\":2}},\"other\":{\"1\":{\"route_type\":3}}}",
    stops: "{\"city\":{\"t\":{\"name\":\"New\",\"lat\":1,\"lon\":2}}}"
))

var initial = NearbyDepartureStreamState(requestId: "request")
let stale = try frame("full", payload(), id: "stale")
let ignoredStale = try initial.accept(stale)
expect(isIgnored(ignoredStale), "Ignore stale request IDs")
guard case .priority(let priority) = try initial.accept(first) else { fatalError("Expected priority") }
expect(priority.local.count == 1, "First phase is published")
let duplicate = try initial.accept(first)
expect(isIgnored(duplicate), "Ignore duplicate priority")
let combined = completed(try initial.accept(remaining))
expect(combined.local.count == 2, "Separate chateaux")
let city = combined.local.first { $0.chateauId == "city" }!
expect(city.closestDistance == 40 && Set(city.headsigns.keys) == ["North", "South"], "Merge directions and distance")
let northItems = city.headsigns["North"]!
expect(northItems.count == 4, "Preserve loop visits, service dates and both scheduled event times")
expect(northItems.first { $0.departureRealtime != nil }?.departureRealtime == 110, "Newer realtime wins")
expect(combined.longDistance.count == 1, "OSM identity ignores coordinate changes")
expect(combined.longDistance[0].departures.count == 2, "Station departures preserve feeds")
expect(combined.longDistance[0].departures.first { $0.chateauId == "city" }?.realtimeDeparture == 110, "Station realtime updated")
expect(Set(combined.routes["city"]!.keys) == ["1", "2"] && combined.routes["other"] != nil, "Merge route lookup tables")
expect(Set(combined.stops["city"]!.keys) == ["s", "t"], "Merge stop lookup tables")
let afterComplete = try initial.accept(remaining)
expect(isIgnored(afterComplete), "Ignore messages after completion")

var refresh = NearbyDepartureStreamState(requestId: "request", publishPriority: false)
let hidden = try refresh.accept(first)
expect(isIgnored(hidden), "Refresh preserves old results until complete")
let refreshed = completed(try refresh.accept(remaining))
expect(refreshed.local.count == 2, "Refresh merges both phases")
var full = NearbyDepartureStreamState(requestId: "request", publishPriority: false)
let empty = completed(try full.accept(frame("full", payload())))
expect(empty.local.isEmpty && empty.longDistance.isEmpty, "Full empty response clears expired data")
var missing = NearbyDepartureStreamState(requestId: "request")
expectError { _ = try missing.accept(remaining) }
var invalid = NearbyDepartureStreamState(requestId: "request")
expectError { _ = try invalid.accept(frame("priority", payload(), complete: true)) }
var failed = NearbyDepartureStreamState(requestId: "request", publishPriority: false)
_ = try failed.accept(first)
let error = try decoder.decode(NearbyDepartureMessage.self, from: Data(#"{"type":"nearby_departures_error","request_id":"request","message":"failure"}"#.utf8))
expectError { _ = try failed.accept(error) }
let legacyError = try decoder.decode(NearbyDepartureMessage.self, from: Data(#"{"type":"error","message":"unknown request"}"#.utf8))
expectError { _ = try failed.accept(legacyError) }
let request = NearbyDepartureRequest(requestId: "request", lat: 34, lon: -118, departureTime: 100, progressive: false)
let encoded = try JSONSerialization.jsonObject(with: request.encoded()) as! [String: Any]
expect(encoded["type"] as? String == "nearby_departures" && encoded["request_id"] as? String == "request", "WebSocket request type and ID")
expect(encoded["limit_per_station"] as? Int == 10 && encoded["limit_per_headsign"] as? Int == 20, "Request limits match Compose")
expect(encoded["departure_time"] as? Int == 100 && encoded["progressive"] as? Bool == false, "Custom time and refresh flag")
print("Nearby departure request, progressive merging, full replacement, and error handling passed")

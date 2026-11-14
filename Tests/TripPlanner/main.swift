import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
// Exercise the exact CI injection fixture, including every query field after re-encoding.
let screenshotData = try Data(contentsOf: URL(fileURLWithPath: "Tests/TripPlanner/screenshot-route.json"))
let screenshotEnvelope = try DirectionsRouteEnvelope.decode(screenshotData)
let screenshotRoundTrip = try JSONSerialization.jsonObject(with: JSONEncoder().encode(screenshotEnvelope)) as! NSDictionary
let screenshotOriginal = try JSONSerialization.jsonObject(with: screenshotData) as! NSDictionary
expect(screenshotRoundTrip == screenshotOriginal, "Screenshot injection preserves the complete wire request")
expect(screenshotEnvelope.query.departure_unix_seconds == 1794598300, "Fixed screenshot departure")
var invalidEnvelope = screenshotOriginal as! [String: Any]
invalidEnvelope["type"] = "cancel"
do {
    _ = try DirectionsRouteEnvelope.decode(JSONSerialization.data(withJSONObject: invalidEnvelope))
    fatalError("Non-route screenshot envelope accepted")
} catch DirectionsError.invalidRequest { }
invalidEnvelope["type"] = "route"
invalidEnvelope["requestId"] = "mismatched-id"
do {
    _ = try DirectionsRouteEnvelope.decode(JSONSerialization.data(withJSONObject: invalidEnvelope))
    fatalError("Mismatched screenshot request IDs accepted")
} catch DirectionsError.invalidRequest { }

let origin = DirectionsLocation(name: "Irvine", lat: 33.64, lon: -117.84)
let destination = DirectionsLocation(name: "Los Angeles", lat: 34.05, lon: -118.24)
let date = Date(timeIntervalSince1970: 1794000000)
let departure = try DirectionsRequest(from: origin, to: destination, date: date, arriveBy: false, options: DirectionsOptions())
let departureJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(departure)) as! [String: Any]
expect(departureJSON["departure_unix_seconds"] as? Int64 == 1794000000, "Departure epoch")
expect(departureJSON["arrival_unix_seconds"] == nil, "Arrival field must be omitted")
expect(departureJSON["preTransitModes"] as? [String] == ["WALK"], "Walking access")
expect(abs((departureJSON["pedestrianSpeed"] as! Double) - 1000 / 840) < 0.0001, "Walking pace to metres per second")
expect(departureJSON["detailed_legs"] as? Bool == true, "Detailed legs")
var cycling = DirectionsOptions(); cycling.cycling = true; cycling.cyclingKmh = 18
let arrival = try DirectionsRequest(from: origin, to: destination, date: date, arriveBy: true, options: cycling)
let arrivalJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(arrival)) as! [String: Any]
expect(arrivalJSON["departure_unix_seconds"] == nil, "Departure omitted for arrive by")
expect(arrivalJSON["arrival_unix_seconds"] as? Int64 == 1794000000, "Arrival epoch")
expect(arrivalJSON["postTransitModes"] as? [String] == ["BIKE"], "Cycling egress")
expect(arrivalJSON["cyclingSpeed"] as? Double == 5, "km/h to m/s")
do {
    _ = try DirectionsRequest(from: DirectionsLocation(name: "Invalid", lat: .nan, lon: 0), to: destination, date: date, arriveBy: false, options: cycling)
    fatalError("Invalid endpoint accepted")
} catch DirectionsError.invalidRequest { }

let known = decodeDirectionsPolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 5)
expect(known.count == 3 && known[0] == DirectionsCoordinate(lat: 38.5, lon: -120.2), "Standard polyline")
for malformed in ["_", "?", "!!!!!!!!", String(repeating: "~", count: 30)] {
    expect(decodeDirectionsPolyline(malformed).isEmpty, "Malformed geometry: \(malformed)")
}
expect(decodeDirectionsPolyline("??", precision: -1).isEmpty, "Invalid precision")
expect(parseDirectionsCoordinate("34.05, -118.24")?.lon == -118.24, "Signed decimal")
expect(parseDirectionsCoordinate("34.05 N 118.24 W")?.lon == -118.24, "Cardinal decimal")
expect(parseDirectionsCoordinate("34° 3′ 0″ N, 118° 15′ 0″ W")?.lon == -118.25, "DMS")
expect(parseDirectionsCoordinate("91, 0") == nil, "Latitude range")
expect(parseDirectionsCoordinate("-34 N, 118 W") == nil, "Conflicting sign")
expect(parseDirectionsCoordinate("NaN, 0") == nil, "Nonfinite coordinate")

let fixture = #"{"itineraries":[{"startTime":"2026-11-07T10:00:00Z","endTime":"2026-11-07T11:00:00.000Z","legs":[{"mode":"RAIL","routeShortName":"R","unknown":true,"from":{"name":"A","lat":0,"lon":0.25},"to":{"name":"B","lat":0,"lon":0.75},"legGeometry":{"points":"???_c`|@"}}]}],"direct":[{"startTime":"2026-11-07T10:00:00Z","endTime":"2026-11-07T12:00:00Z","legs":[{"mode":"WALK"}]}],"extra":"ignored"}"#
let plan = try JSONDecoder().decode(DirectionsPlan.self, from: Data(fixture.utf8))
expect(plan.journeys.count == 2 && plan.journeys[0].seconds == 3600, "Optional fields, fractional ISO timestamps, backend ranking")
let clipped = directionsCoordinates(plan.journeys[0].legs[0])
expect(clipped.count == 2 && abs(clipped[0].lon - 0.25) < 0.0001 && abs(clipped[1].lon - 0.75) < 0.0001, "Clip within a single shape segment")
var reversed = plan.journeys[0].legs[0]
let oldFrom = reversed.from
reversed.from = reversed.to
reversed.to = oldFrom
let reverseCoordinates = directionsCoordinates(reversed)
expect(reverseCoordinates.first == clipped.last && reverseCoordinates.last == clipped.first, "Reversed shape")
expect(directionsDistance(plan.journeys[0].legs[0])! > 55_000, "Distance uses clipped geometry")
let points = [DirectionsCoordinate(lat: 34, lon: -118), DirectionsCoordinate(lat: 34.1, lon: -118.1)]
expect(decodeDirectionsPolyline(encodeDirectionsPolyline(points)) == points, "Geometry round trip")
let widths = directionsTimelineWidths(plan.journeys[0].legs + plan.journeys[1].legs, width: 160)
expect(widths.count == 2 && widths.allSatisfy { $0 >= 48 } && abs(widths.reduce(0, +) - 160) < 0.001, "Minimum timeline widths and total")
expect(plan.journeys[0].previewTimeGroups.departure.count == 1, "No duplicate boarding time when starting at a stop")
var consecutive = plan.journeys[1]
consecutive.legs = [DirectionsLeg(mode: "WALK", duration: 60), DirectionsLeg(mode: "WALK", duration: 120)]
expect(consecutive.detailLegs.count == 1 && consecutive.detailLegs[0].seconds == 180, "Consecutive walks combined")
print("Trip planner contract, geometry, and presentation fixtures passed")

// Pagination/streaming parity with catenary-compose TripPlannerStreamingTest.kt.
func streamJourney(id: String, hour: Int, mode: String = "BUS") -> DirectionsItinerary {
    DirectionsItinerary(startTime: "2026-11-09T\(hour):00:00Z", endTime: "2026-11-09T\(hour):30:00Z",
        legs: [DirectionsLeg(mode: mode)], id: id)
}

var cyclingPageOptions = DirectionsOptions(); cyclingPageOptions.cycling = true
let pageBase = try DirectionsRequest(from: DirectionsLocation(name: "A", lat: 34.0, lon: -118.0),
    to: DirectionsLocation(name: "B", lat: 35.0, lon: -117.0), date: Date(timeIntervalSince1970: 1793642246),
    arriveBy: true, options: cyclingPageOptions)
let initialQuery = directionsPageQuery(base: pageBase, direction: .before, requestId: "r")
let earlierQuery = directionsPageQuery(base: pageBase, direction: .before, cursor: "opaque-before", requestId: "r")
let laterQuery = directionsPageQuery(base: pageBase, direction: .after, cursor: "opaque-after", requestId: "r")
expect(initialQuery.number_of_results_before == 8 && initialQuery.number_of_results_after == 0, "Initial page uses the full web page size")
expect(earlierQuery.number_of_results_before == 4 && earlierQuery.number_of_results_after == 0, "Earlier follow-up page is smaller")
expect(laterQuery.number_of_results_before == 0 && laterQuery.number_of_results_after == 5, "Later follow-up page is smaller")
expect(laterQuery.page_cursor == "opaque-after", "Cursor carried onto the page query")
expect(initialQuery.pedestrianSpeed == pageBase.pedestrianSpeed && initialQuery.cyclingSpeed == pageBase.cyclingSpeed, "Base query fields preserved")

let earlierPage = DirectionsPlan(itineraries: [streamJourney(id: "earlier", hour: 10)])
let firstPage = DirectionsPlan(itineraries: [streamJourney(id: "initial", hour: 11)], direct: [streamJourney(id: "walk", hour: 10, mode: "WALK")])
let laterPage = DirectionsPlan(itineraries: [streamJourney(id: "later", hour: 12), streamJourney(id: "initial", hour: 11)],
    direct: [streamJourney(id: "walk", hour: 10, mode: "WALK")])
let merged = mergeDirectionsPages([firstPage, laterPage, earlierPage])
expect(merged.map(\.identity) == ["earlier", "walk", "initial", "later"], "Snapshots dedupe and connections stay chronological")

let streamState = DirectionsStreamState(requestId: "request-1")
let finalPage = DirectionsPlan(itineraries: [streamJourney(id: "final", hour: 12)], previousPageCursor: "older", nextPageCursor: "newer")
let partialPage = DirectionsPlan(itineraries: [streamJourney(id: "partial", hour: 11)])
if case .ignored = try streamState.accept(DirectionsStreamMessage(type: "accepted", requestId: "request-1", sequence: nil, response: nil, message: nil)) {} else { fatalError("Unknown frame type must be ignored") }
if case .ignored = try streamState.accept(DirectionsStreamMessage(type: "snapshot", requestId: "other", sequence: 10, response: finalPage, message: nil)) {} else { fatalError("Other request's frame must be ignored") }
guard case .page(let firstAccepted) = try streamState.accept(DirectionsStreamMessage(type: "snapshot", requestId: "request-1", sequence: 2, response: partialPage, message: nil)) else { fatalError("First snapshot must be accepted") }
expect(firstAccepted.itineraries?.first?.id == "partial", "First snapshot's page is returned")
if case .ignored = try streamState.accept(DirectionsStreamMessage(type: "snapshot", requestId: "request-1", sequence: 1, response: finalPage, message: nil)) {} else { fatalError("Stale sequence must be ignored") }
if case .ignored = try streamState.accept(DirectionsStreamMessage(type: "snapshot", requestId: "request-1", sequence: 2, response: finalPage, message: nil)) {} else { fatalError("Non-increasing sequence must be ignored") }
guard case .complete(let completedPage) = try streamState.accept(DirectionsStreamMessage(type: "complete", requestId: "request-1", sequence: nil, response: finalPage, message: nil)) else { fatalError("Complete must terminate the stream") }
expect(completedPage?.itineraries?.first?.id == "final", "Complete always wins over the last snapshot")
do {
    _ = try streamState.accept(DirectionsStreamMessage(type: "error", requestId: "request-1", sequence: nil, response: nil, message: "boom"))
    fatalError("Backend error frame must throw")
} catch DirectionsStreamError.backend(let message) { expect(message == "boom", "Backend error message propagated") }

let wireData = Data(#"""
{"type":"complete","requestId":"r","response":{"itineraries":[
  {"id":"stable","startTime":"2026-11-09T10:00:00Z","endTime":"2026-11-09T10:30:00Z","legs":[]}],
  "previousPageCursor":"before","nextPageCursor":"after","metadata":{}}}
"""#.utf8)
let wireMessage = try JSONDecoder().decode(DirectionsStreamMessage.self, from: wireData)
expect(wireMessage.response?.itineraries?.first?.identity == "stable", "Stable id decoded from camelCase wire fields")
expect(wireMessage.response?.previousPageCursor == "before" && wireMessage.response?.nextPageCursor == "after", "Pagination cursors decoded")

var outOfRangeOptions = DirectionsOptions(); outOfRangeOptions.accessSeconds = 9000; outOfRangeOptions.egressSeconds = 0
let unclamped = try DirectionsRequest(from: origin, to: destination, date: date, arriveBy: false, options: outOfRangeOptions)
expect(unclamped.maxPreTransitTime == 3600 && unclamped.maxPostTransitTime == 1, "Access/egress budgets clamp to Edelweiss's 1...3600 contract")
let unclampedJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(unclamped)) as! [String: Any]
expect(unclampedJSON["timetable_view"] as? Bool == true && unclampedJSON["timeout_seconds"] as? Int == 8, "New Edelweiss contract fields are always sent")

print("Trip planner pagination, streaming, and wire-contract fixtures passed")

// Dense train interchanges keep internal walks compact, while substantial transfers stay visible.
let railLeg = DirectionsLeg(mode: "RAIL", duration: 600, routeType: 2)
let internalWalk = DirectionsLeg(mode: "WALK", duration: 360)
let transferJourney = DirectionsItinerary(startTime: "2099-01-01T10:00:00Z", endTime: "2099-01-01T11:00:00Z",
    legs: [railLeg, internalWalk, railLeg])
expect(transferJourney.previewLegs.count == 2, "Six-minute internal train transfer is hidden")
var longerTransfer = transferJourney
longerTransfer.legs[1].duration = 480
expect(longerTransfer.previewLegs.count == 3, "Eight-minute train transfer stays visible")
let transferWidths = directionsTimelineWidths(longerTransfer.legs, width: 124)
expect(transferWidths == [48, 28, 48], "Walking transfer reserves less width than train badges")
let narrowWidths = directionsTimelineWidths(longerTransfer.legs, width: 62)
expect(narrowWidths == [24, 14, 24], "Narrow timeline scales minimum widths proportionally")
expect(transferJourney.canBeSaved && !firstPage.journeys[0].canBeSaved, "Only future journeys can be newly starred")
do {
    _ = try DirectionsStreamState(requestId: "missing").accept(DirectionsStreamMessage(type: "complete", requestId: "missing", sequence: nil, response: nil, message: nil))
    fatalError("Missing authoritative final response accepted")
} catch let error as URLError { expect(error.code == .cannotParseResponse, "Malformed completion is a transport failure") }
print("Compact transfers, save eligibility, and malformed completion checks passed")
expect(directionsPageAtEdge(direction: nil, firstVisible: 0, lastVisible: 7, count: 8) == nil, "Initial layout never auto-pages")
expect(directionsPageAtEdge(direction: .before, firstVisible: 1, lastVisible: 3, count: 8) == .before, "Scrolling up near the top loads earlier")
expect(directionsPageAtEdge(direction: .after, firstVisible: 4, lastVisible: 6, count: 8) == .after, "Scrolling down near the bottom loads later")
expect(directionsPageAtEdge(direction: .before, firstVisible: 4, lastVisible: 7, count: 8) == nil, "Scrolling up at the bottom never loads later")
expect(directionsPageAtEdge(direction: .after, firstVisible: nil, lastVisible: nil, count: 8) == nil, "Offscreen results never page")
expect(directionsPageAtEdge(direction: .after, firstVisible: 0, lastVisible: 0, count: 0) == nil, "Empty results never page")
print("Scroll direction and pagination edge checks passed")

// Named server zones must win over the device zone and 12-hour clock preferences.
expect(directionsClock("2026-07-01T20:05:00Z", timezone: "America/Los_Angeles") == "13:05", "Summer DST and 24-hour clock")
expect(directionsClock("2026-01-01T20:05:00Z", timezone: "America/Los_Angeles") == "12:05", "Winter timezone offset")
expect(directionsClock("2026-07-01T20:05:00Z", timezone: "Asia/Tokyo") == "05:05", "Arrival across midnight")
expect(directionsClock("bad", timezone: "UTC") == "—", "Invalid timestamp placeholder")
expect(directionsDayHeading("2026-07-01T23:30:00Z", "2026-07-02T00:30:00Z", timezone: "America/Los_Angeles") == nil, "UTC midnight is not local midnight")
expect(directionsDayHeading("2026-07-02T06:30:00Z", "2026-07-02T07:30:00Z", timezone: "America/Los_Angeles") != nil, "Local midnight heading")
let zonedJourney = try JSONDecoder().decode(DirectionsItinerary.self, from: Data("""
{"startTime":"2026-07-01T19:55:00Z","endTime":"2026-07-02T01:15:00Z","legs":[
{"mode":"WALK","startTime":"2026-07-01T19:55:00Z","endTime":"2026-07-01T20:05:00Z"},
{"mode":"RAIL","startTime":"2026-07-01T20:05:00Z","endTime":"2026-07-02T01:05:00Z","from":{"timezone":"America/Los_Angeles"},"to":{"timezone":"America/Denver"},"intermediateStops":[{"timezone":"America/Phoenix"}]},
{"mode":"WALK","startTime":"2026-07-02T01:05:00Z","endTime":"2026-07-02T01:15:00Z"}]}
""".utf8))
expect(zonedJourney.previewTimeGroups.departure.map(\.endpoint) == [true, false], "Overall departure is bold; boarding is secondary")
expect(zonedJourney.previewTimeGroups.arrival.map(\.endpoint) == [false, true], "Alighting is secondary; overall arrival is bold")
expect(zonedJourney.previewTimeGroups.departure.allSatisfy { $0.timezone == "America/Los_Angeles" }, "Departure zone uses boarding stop")
expect(zonedJourney.previewTimeGroups.arrival.allSatisfy { $0.timezone == "America/Denver" }, "Arrival zone uses alighting stop")
expect(zonedJourney.legs[1].intermediateStops?.first?.timezone == "America/Phoenix", "Intermediate stop timezone decoded")

// Trip info uses the service date/start time rather than the boarding date (overnight trips).
let tripInfoFixture = #"{"mode":"BUS","chateau":"test","tripId":"loop","routeId":"1","routeType":3,"tripStartDate":"20261113","tripStartTime":"25:00:00","startTime":"2026-11-14T09:20:00Z","endTime":"2026-11-14T09:30:00Z","from":{"name":"A","stopId":"a"},"to":{"name":"A","stopId":"a"},"fromStopSequence":30,"toStopSequence":50}"#
let tripInfoLeg = try JSONDecoder().decode(DirectionsLeg.self, from: Data(tripInfoFixture.utf8))
let tripSelection = tripInfoLeg.singleTripInfo!
expect(tripSelection.chateauID == "test" && tripSelection.tripID == "loop" && tripSelection.routeID == "1", "Exact trip identifiers")
expect(tripSelection.startDate == "20261113" && tripSelection.startTime == "25:00:00" && tripSelection.routeType == 3, "Overnight trip instance")
let restoredTripLeg = try JSONDecoder().decode(DirectionsLeg.self, from: JSONEncoder().encode(tripInfoLeg))
expect(restoredTripLeg.singleTripInfo == tripSelection, "Saved journeys retain trip info metadata")
let segment = tripSelection.journeySegment!
func tripStop(_ id: String, _ sequence: Int?, _ time: Int64?) throws -> SingleTripStopTime {
    var json: [String: Any] = ["stop_id": id, "longitude": 0, "latitude": 0]
    if let sequence { json["gtfs_stop_sequence"] = sequence }
    if let time { json["scheduled_departure_time_unix_seconds"] = time; json["scheduled_arrival_time_unix_seconds"] = time }
    return try JSONDecoder().decode(SingleTripStopTime.self, from: JSONSerialization.data(withJSONObject: json))
}
let loopStops = try [tripStop("a", 10, segment.from.time - 600), tripStop("b", 20, nil),
    tripStop("a", 30, segment.from.time), tripStop("b", 40, nil), tripStop("a", 50, segment.to.time), tripStop("c", 60, nil)]
let selectedRange = JourneyTripRange(from: 2, to: 4)
expect(JourneyTripRange.resolve(stops: loopStops, segment: segment) == selectedRange, "Sequences distinguish loop stop visits")
let sequenceFreeStops = try loopStops.map { try tripStop($0.stopID, nil, $0.scheduledDepartureTimeUnixSeconds) }
expect(JourneyTripRange.resolve(stops: sequenceFreeStops, segment: segment) == selectedRange, "Scheduled times distinguish repeated visits when sequence is absent")
expect(JourneyTripRange.resolve(stops: loopStops, segment: nil) == nil, "Ordinary trips have no selected segment")
expect(JourneyTripRange.resolve(stops: loopStops, segment: JourneyTripSegment(from: segment.to, to: segment.from)) == nil, "Reversed selections fail safely")
let missingEndpoint = JourneyTripEndpoint(stopID: "missing", sequence: 30, time: segment.from.time)
expect(JourneyTripRange.resolve(stops: loopStops, segment: JourneyTripSegment(from: missingEndpoint, to: segment.to)) == nil, "Missing stops fail safely")
expect(selectedRange.stop(1) == JourneyStopPresentation(active: false, endpoint: false, incomingActive: false, outgoingActive: false), "Earlier stops muted")
expect(selectedRange.stop(2) == JourneyStopPresentation(active: true, endpoint: true, incomingActive: false, outgoingActive: true), "Boarding pearl splits contrast")
expect(selectedRange.stop(3) == JourneyStopPresentation(active: true, endpoint: false, incomingActive: true, outgoingActive: true), "Intermediate stop fully active")
expect(selectedRange.stop(4) == JourneyStopPresentation(active: true, endpoint: true, incomingActive: true, outgoingActive: false), "Alighting pearl splits contrast")
expect(!selectedRange.stop(5).active, "Later stops muted")
for field in ["tripId", "tripStartDate", "chateau", "startTime"] {
    var missing = try JSONSerialization.jsonObject(with: Data(tripInfoFixture.utf8)) as! [String: Any]
    missing.removeValue(forKey: field)
    let leg = try JSONDecoder().decode(DirectionsLeg.self, from: JSONSerialization.data(withJSONObject: missing))
    expect(leg.singleTripInfo == nil, "Incomplete trip metadata hides navigation: \(field)")
}
var streetTrip = tripInfoLeg; streetTrip.mode = "WALK"
expect(streetTrip.singleTripInfo == nil, "Street legs do not offer trip info")
var badTimeTrip = tripInfoLeg; badTimeTrip.startTime = "invalid"
expect(badTimeTrip.singleTripInfo == nil, "Invalid times do not offer trip info")
let oldLeg = try JSONDecoder().decode(DirectionsLeg.self, from: Data(#"{"mode":"BUS"}"#.utf8))
expect(oldLeg.singleTripInfo == nil, "Older saved journeys remain readable")
print("Trip info metadata, overnight services, loop matching and segment presentation passed")

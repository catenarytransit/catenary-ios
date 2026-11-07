import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
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

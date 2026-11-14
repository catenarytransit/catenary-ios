import Foundation

struct DirectionsTimeMarker: Equatable {
    let time: String
    let endpoint: Bool
    var timezone: String? = nil
}
struct DirectionsTimeGroups: Equatable {
    let departure: [DirectionsTimeMarker]
    let arrival: [DirectionsTimeMarker]
}

extension DirectionsItinerary {
    var departureTimezone: String? {
        legs.first(where: { !$0.street })?.from?.timezone ?? legs.first?.from?.timezone
    }
    var arrivalTimezone: String? {
        legs.last(where: { !$0.street })?.to?.timezone ?? legs.last?.to?.timezone
    }
    var previewTimeGroups: DirectionsTimeGroups {
        guard let first = legs.firstIndex(where: { !$0.street }), let last = legs.lastIndex(where: { !$0.street }) else {
            return DirectionsTimeGroups(departure: [.init(time: startTime, endpoint: true, timezone: departureTimezone)], arrival: [.init(time: endTime, endpoint: true, timezone: arrivalTimezone)])
        }
        func atStop(_ streetLegs: ArraySlice<DirectionsLeg>) -> Bool {
            var meters = 0.0
            for leg in streetLegs {
                guard let distance = directionsDistance(leg) else { return false }
                meters += distance
            }
            return meters < 25
        }
        let boarding = legs[first].startTime ?? (first > 0 ? legs[first - 1].endTime : nil)
        let alighting = legs[last].endTime ?? (last + 1 < legs.count ? legs[last + 1].startTime : endTime)
        let originAtStop = atStop(legs[..<first])
        let destinationAtStop = atStop(legs[(last + 1)...])
        var departure = [DirectionsTimeMarker(time: startTime, endpoint: true, timezone: departureTimezone)]
        var arrival: [DirectionsTimeMarker] = []
        if !originAtStop, let boarding, directionsDate(boarding) != nil, directionsDate(boarding) != directionsDate(startTime) {
            departure.append(.init(time: boarding, endpoint: false, timezone: legs[first].from?.timezone))
        }
        if !destinationAtStop, let alighting, directionsDate(alighting) != nil, directionsDate(alighting) != directionsDate(endTime) {
            arrival.append(.init(time: alighting, endpoint: false, timezone: legs[last].to?.timezone))
        }
        arrival.append(.init(time: endTime, endpoint: true, timezone: arrivalTimezone))
        return DirectionsTimeGroups(departure: departure, arrival: arrival)
    }
    var detailLegs: [DirectionsLeg] {
        var result: [DirectionsLeg] = []
        for leg in legs {
            if var previous = result.last, previous.street, leg.street, previous.mode == leg.mode {
                let a = directionsCoordinates(previous), b = directionsCoordinates(leg)
                let combinedDuration = previous.seconds + leg.seconds
                previous.to = leg.to; previous.endTime = leg.endTime; previous.toPlatform = leg.toPlatform
                previous.duration = combinedDuration
                previous.legGeometry = !a.isEmpty && !b.isEmpty
                    ? DirectionsGeometry(points: encodeDirectionsPolyline(a + b), precision: 6) : nil
                result[result.count - 1] = previous
            } else { result.append(leg) }
        }
        return result
    }
    var previewLegs: [DirectionsLeg] {
        let combined = detailLegs
        return combined.enumerated().filter { index, leg in
            if !leg.street { return true }
            if index == 0 || index == combined.count - 1 { return (directionsDistance(leg) ?? 25) >= 25 }
            let trains = combined[index - 1].routeType == 2 && combined[index + 1].routeType == 2
            return leg.seconds > (trains ? 420 : 300)
        }.map(\.element)
    }
}

func directionsTimelineMinimums(_ legs: [DirectionsLeg], minimum: Double = 48) -> [Double] {
    legs.indices.map { index in
        let transfer = index > 0 && index < legs.count - 1 && legs[index].mode.uppercased() == "WALK"
            && !legs[index - 1].street && !legs[index + 1].street
        return transfer ? min(28, minimum) : minimum
    }
}

/// Allocate icon widths before distributing the remaining width by duration.
func directionsTimelineWidths(_ legs: [DirectionsLeg], width: Double, minimum: Double = 48) -> [Double] {
    guard !legs.isEmpty else { return [] }
    let weights = legs.map { $0.seconds.isFinite && $0.seconds > 0 ? $0.seconds : 1 }
    var pixels = Array(repeating: 0.0, count: legs.count)
    var remaining = Array(legs.indices)
    var available = max(1, width)
    let minimums = directionsTimelineMinimums(legs, minimum: minimum)
    let totalMinimum = minimums.reduce(0, +)
    if totalMinimum > available { return minimums.map { $0 * available / totalMinimum } }
    while !remaining.isEmpty {
        let total = remaining.reduce(0) { $0 + weights[$1] }
        let small = remaining.filter { available * weights[$0] / total < minimums[$0] }
        if small.isEmpty {
            for index in remaining { pixels[index] = available * weights[index] / total }
            break
        }
        for index in small { pixels[index] = minimums[index]; available -= minimums[index] }
        remaining.removeAll { small.contains($0) }
    }
    return pixels.map { max(0.001, $0) }
}

func encodeDirectionsPolyline(_ points: [DirectionsCoordinate]) -> String {
    var lat: Int64 = 0, lon: Int64 = 0
    var bytes: [UInt8] = []
    func append(_ delta: Int64) {
        var value = delta < 0 ? UInt64(~(delta << 1)) : UInt64(delta << 1)
        while value >= 32 {
            bytes.append(UInt8((value & 31) | 32) + 63); value >>= 5
        }
        bytes.append(UInt8(value) + 63)
    }
    for point in points {
        let nextLat = Int64((point.lat * 1e6).rounded()), nextLon = Int64((point.lon * 1e6).rounded())
        append(nextLat - lat); append(nextLon - lon); lat = nextLat; lon = nextLon
    }
    return String(decoding: bytes, as: UTF8.self)
}

/// Keep server wall times in their named zone (including DST), independent of device preferences.
func directionsTimeZone(_ identifier: String?) -> TimeZone {
    identifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
}
func directionsClock(_ time: String?, timezone: String? = nil) -> String {
    guard let date = directionsDate(time) else { return "—" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = directionsTimeZone(timezone)
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}
func directionsDayHeading(_ previous: String?, _ time: String, timezone: String?) -> String? {
    guard let previous = directionsDate(previous), let date = directionsDate(time) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = directionsTimeZone(timezone)
    guard !calendar.isDate(previous, inSameDayAs: date) else { return nil }
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.timeZone = calendar.timeZone
    formatter.dateStyle = .full
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

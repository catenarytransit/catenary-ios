import Foundation

struct DirectionsTimeMarker: Equatable {
    let time: String
    let transit: Bool
}
struct DirectionsTimeGroups: Equatable {
    let departure: [DirectionsTimeMarker]
    let arrival: [DirectionsTimeMarker]
}

extension DirectionsItinerary {
    var previewTimeGroups: DirectionsTimeGroups {
        guard let first = legs.firstIndex(where: { !$0.street }), let last = legs.lastIndex(where: { !$0.street }) else {
            return DirectionsTimeGroups(departure: [.init(time: startTime, transit: false)], arrival: [.init(time: endTime, transit: false)])
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
        var departure = [DirectionsTimeMarker(time: startTime, transit: originAtStop || directionsDate(boarding) == directionsDate(startTime))]
        var arrival: [DirectionsTimeMarker] = []
        if !originAtStop, let boarding, directionsDate(boarding) != nil, directionsDate(boarding) != directionsDate(startTime) {
            departure.append(.init(time: boarding, transit: true))
        }
        if !destinationAtStop, let alighting, directionsDate(alighting) != nil, directionsDate(alighting) != directionsDate(endTime) {
            arrival.append(.init(time: alighting, transit: true))
        }
        arrival.append(.init(time: endTime, transit: destinationAtStop || directionsDate(alighting) == directionsDate(endTime)))
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
            return leg.seconds > 300
        }.map(\.element)
    }
}

/// Allocate a minimum icon width before distributing the remaining width by duration.
func directionsTimelineWidths(_ legs: [DirectionsLeg], width: Double, minimum: Double = 48) -> [Double] {
    guard !legs.isEmpty else { return [] }
    let weights = legs.map { $0.seconds.isFinite && $0.seconds > 0 ? $0.seconds : 1 }
    var pixels = Array(repeating: 0.0, count: legs.count)
    var remaining = Array(legs.indices)
    var available = max(1, width)
    let floor = min(minimum, available / Double(legs.count))
    while !remaining.isEmpty {
        let total = remaining.reduce(0) { $0 + weights[$1] }
        let small = remaining.filter { available * weights[$0] / total < floor }
        if small.isEmpty {
            for index in remaining { pixels[index] = available * weights[index] / total }
            break
        }
        for index in small { pixels[index] = floor; available -= floor }
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

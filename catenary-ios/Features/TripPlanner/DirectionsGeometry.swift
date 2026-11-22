import Foundation

struct DirectionsCoordinate: Equatable {
    let lat: Double
    let lon: Double
}
func decodeDirectionsPolyline(_ encoded: String, precision: Int = 6) -> [DirectionsCoordinate] {
    guard (0...8).contains(precision) else { return [] }
    let bytes = Array(encoded.utf8)
    var index = 0, lat: Int64 = 0, lon: Int64 = 0
    let scale = pow(10.0, Double(precision))
    func next() -> Int64? {
        var value: UInt64 = 0, shift = 0
        while index < bytes.count, shift <= 55 {
            let byte = Int(bytes[index]) - 63
            index += 1
            guard (0...63).contains(byte) else { return nil }
            value |= UInt64(byte & 31) << shift
            if byte < 32 { return value & 1 == 0 ? Int64(value >> 1) : ~Int64(value >> 1) }
            shift += 5
        }
        return nil
    }
    var result: [DirectionsCoordinate] = []
    while index < bytes.count {
        guard let a = next(), let b = next() else { return [] }
        let (nextLat, overflowLat) = lat.addingReportingOverflow(a)
        let (nextLon, overflowLon) = lon.addingReportingOverflow(b)
        guard !overflowLat, !overflowLon else { return [] }
        lat = nextLat; lon = nextLon
        let point = DirectionsCoordinate(lat: Double(lat) / scale, lon: Double(lon) / scale)
        guard (-90...90).contains(point.lat), (-180...180).contains(point.lon) else { return [] }
        result.append(point)
    }
    return result
}
private func longitudeDelta(_ a: Double, _ b: Double) -> Double {
    (a - b + 540).truncatingRemainder(dividingBy: 360) - 180
}
func directionsDistance(_ a: DirectionsCoordinate, _ b: DirectionsCoordinate) -> Double {
    let radians = Double.pi / 180
    let h = pow(sin((b.lat - a.lat) * radians / 2), 2)
        + cos(a.lat * radians) * cos(b.lat * radians) * pow(sin(longitudeDelta(b.lon, a.lon) * radians / 2), 2)
    return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
}
private struct ShapeProjection {
    let index: Int
    let fraction: Double
    let point: DirectionsCoordinate
    let distance: Double
    var position: Double { Double(index) + fraction }
}
// Match Compose's stop projections, including reversed GTFS shapes and nearby loop candidates.
func directionsCoordinates(_ leg: DirectionsLeg) -> [DirectionsCoordinate] {
    guard let geometry = leg.legGeometry, let encoded = geometry.points else { return [] }
    let points = decodeDirectionsPolyline(encoded, precision: geometry.precision ?? 6)
    guard !leg.street, points.count >= 2, let from = leg.from?.location, let to = leg.to?.location else { return points }
    let a = DirectionsCoordinate(lat: from.lat, lon: from.lon), b = DirectionsCoordinate(lat: to.lat, lon: to.lon)
    guard directionsDistance(a, b) >= 20 else { return points }
    func projections(_ stop: DirectionsCoordinate) -> [ShapeProjection] {
        let scale = 111195 * max(0.00001, cos(stop.lat * .pi / 180))
        var candidates: [ShapeProjection] = []
        for i in 0..<(points.count - 1) {
            let ax = longitudeDelta(points[i].lon, stop.lon) * scale
            let ay = (points[i].lat - stop.lat) * 111195
            let dx = longitudeDelta(points[i + 1].lon, stop.lon) * scale - ax
            let dy = (points[i + 1].lat - stop.lat) * 111195 - ay
            let square = dx * dx + dy * dy
            guard square > 0 else { continue }
            let fraction = min(1, max(0, -(ax * dx + ay * dy) / square))
            let x = ax + fraction * dx, y = ay + fraction * dy
            let distance = hypot(x, y)
            guard distance <= 350 else { continue }
            candidates.append(ShapeProjection(index: i, fraction: fraction,
                point: DirectionsCoordinate(lat: stop.lat + y / 111195,
                    lon: (stop.lon + x / scale + 540).truncatingRemainder(dividingBy: 360) - 180), distance: distance))
        }
        candidates.sort { $0.distance < $1.distance }
        let cutoff = min(350, (candidates.first?.distance ?? 350) + 30)
        return Array(candidates.filter { $0.distance <= cutoff }.prefix(64))
    }
    var chosen: (ShapeProjection, ShapeProjection)?
    var score = Double.infinity
    for start in projections(a) {
        for end in projections(b) where abs(start.position - end.position) >= 1e-8 {
            let candidate = start.distance + end.distance + (start.position > end.position ? 5 : 0)
            if candidate < score { chosen = (start, end); score = candidate }
        }
    }
    guard let (start, end) = chosen else { return points }
    let reverse = start.position > end.position
    let first = reverse ? end : start, last = reverse ? start : end
    var clipped = [first.point]
    for point in points[(first.index + 1)..<(last.index + 1)] where clipped.last != point { clipped.append(point) }
    if clipped.last != last.point { clipped.append(last.point) }
    guard clipped.count >= 2 else { return points }
    return reverse ? Array(clipped.reversed()) : clipped
}
func directionsDistance(_ leg: DirectionsLeg) -> Double? {
    let points = directionsCoordinates(leg)
    guard points.count >= 2 else { return nil }
    return zip(points, points.dropFirst()).reduce(0) { $0 + directionsDistance($1.0, $1.1) }
}

// Decimal and DMS coordinates with signed values or cardinal directions.
func parseDirectionsCoordinate(_ raw: String) -> DirectionsLocation? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: "−", with: "-")
    var pair = text.components(separatedBy: CharacterSet(charactersIn: ",;"))
    if pair.count == 1 {
        if let split = text.firstIndex(of: "N") ?? text.firstIndex(of: "S") {
            pair = [String(text[...split]), String(text[text.index(after: split)...])]
        } else { pair = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty } }
    }
    guard pair.count == 2 else { return nil }
    func component(_ raw: String, latitude: Bool) -> Double? {
        let hemispheres = raw.filter { "NSEW".contains($0) }
        guard hemispheres.count <= 1, !hemispheres.contains(where: { (latitude ? "EW" : "NS").contains($0) }) else { return nil }
        let parts = raw.components(separatedBy: CharacterSet(charactersIn: "NSEW°º′'″\"").union(.whitespacesAndNewlines)).filter { !$0.isEmpty }
        let values = parts.compactMap(Double.init)
        guard values.count == parts.count, (1...3).contains(values.count), values.allSatisfy(\.isFinite),
              values.dropFirst().allSatisfy({ (0..<60).contains($0) }) else { return nil }
        if values[0] < 0, hemispheres.contains(where: { "NE".contains($0) }) { return nil }
        let magnitude = abs(values[0]) + (values.count > 1 ? values[1] / 60 : 0) + (values.count > 2 ? values[2] / 3600 : 0)
        return magnitude * (values[0] < 0 || hemispheres.contains(where: { "SW".contains($0) }) ? -1 : 1)
    }
    guard let lat = component(pair[0], latitude: true), let lon = component(pair[1], latitude: false) else { return nil }
    let location = DirectionsLocation(name: String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), lat, lon), lat: lat, lon: lon)
    return location.isValid ? location : nil
}

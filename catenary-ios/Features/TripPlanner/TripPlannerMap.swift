import MapLibre
import SwiftUI

/// Persistent native layers: changing the planner never rebuilds the base map.
final class TripPlannerMapCoordinator: ObservableObject {
    private weak var map: MLNMapView?
    private weak var installedStyle: MLNStyle?
    private var layers = Set<String>()
    private var sources = Set<String>()
    private var previous: DirectionsMapState?
    private var fitted: UUID?

    func styleLoaded(state: DirectionsMapState) {
        guard let map else { return }
        previous = nil
        update(map: map, state: state)
    }

    func update(map: MLNMapView, state: DirectionsMapState) {
        self.map = map
        guard let style = map.style else { return }
        if installedStyle !== style {
            installedStyle = style; layers = []; sources = []; previous = nil
        }
        guard previous != state else { return }
        previous = state
        for id in layers { if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) } }
        for id in sources { if let source = style.source(withIdentifier: id) { style.removeSource(source) } }
        layers = []; sources = []
        guard state.visible else { return }
        let journeys = Array(state.itineraries.enumerated())
        var bounds: [CLLocationCoordinate2D] = []
        // Draw selected journey last so its full colour remains visible.
        let ordered = journeys.sorted { ($0.offset == state.selected ? 1 : 0) < ($1.offset == state.selected ? 1 : 0) }
        for (index, journey) in ordered {
            for (legIndex, leg) in journey.legs.enumerated() {
                var coordinates = directionsCoordinates(leg).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                if !state.details || index == state.selected { bounds += coordinates }
                guard coordinates.count >= 2 else { continue }
                let id = "planner-\(index)-\(legIndex)"
                let source = MLNShapeSource(identifier: id, shape: MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count)), options: nil)
                style.addSource(source); sources.insert(id)
                let line = MLNLineStyleLayer(identifier: id, source: source)
                line.lineColor = NSExpression(forConstantValue: index == state.selected ? leg.uiColor : UIColor.systemGray)
                line.lineWidth = NSExpression(forConstantValue: index == state.selected ? 6 : 4)
                line.lineOpacity = NSExpression(forConstantValue: index == state.selected ? 1 : 0.35)
                if leg.street { line.lineDashPattern = NSExpression(forConstantValue: [1, 1.5]) }
                style.addLayer(line); layers.insert(id)
            }
        }
        if state.showTransfers, state.itineraries.indices.contains(state.selected) {
            let transit = state.itineraries[state.selected].legs.filter { !$0.street }
            var points: [DirectionsLocation] = []
            for (a, b) in zip(transit, transit.dropFirst()) {
                points += [a.to?.location, b.from?.location].compactMap { $0 }
            }
            for (index, point) in points.enumerated() {
                addPoint(point.coordinate, id: "planner-transfer-\(index)", color: .systemGray, radius: 5, style: style)
            }
        }
        for (index, point) in [state.origin, state.destination].enumerated() {
            if let point {
                bounds.append(point.coordinate)
                addEndpoint(point.coordinate, origin: index == 0, style: style)
            }
        }
        if state.fitRevision != fitted, !state.itineraries.isEmpty, let first = bounds.first {
            fitted = state.fitRevision
            var south = first.latitude, north = first.latitude, west = first.longitude, east = first.longitude
            for point in bounds {
                south = min(south, point.latitude); north = max(north, point.latitude)
                west = min(west, point.longitude); east = max(east, point.longitude)
            }
            let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: south, longitude: west), ne: CLLocationCoordinate2D(latitude: north, longitude: east))
            map.setVisibleCoordinateBounds(bounds, edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 40, right: 40), animated: true)
        }
    }
    private func addEndpoint(_ coordinate: CLLocationCoordinate2D, origin: Bool, style: MLNStyle) {
        let id = origin ? "planner-start" : "planner-end"
        if style.image(forName: id) == nil {
            // Same green start and checkerboard destination artwork as Compose's XML vectors.
            let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
                context.cgContext.scaleBy(x: 0.4, y: 0.4)
                let circle = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 46, height: 46))
                (origin ? UIColor(red: 113/255, green: 173/255, blue: 65/255, alpha: 1) : .white).setFill()
                circle.fill()
                let dark = UIColor(white: 0.102, alpha: 1)
                if !origin {
                    context.cgContext.saveGState(); circle.addClip(); dark.setFill()
                    for rect in [CGRect(x: 32, y: 18, width: 17, height: 14), CGRect(x: 18, y: 2, width: 14, height: 16),
                                 CGRect(x: 18, y: 32, width: 14, height: 15), CGRect(x: 2, y: 18, width: 16, height: 14)] {
                        UIBezierPath(rect: rect).fill()
                    }
                    context.cgContext.restoreGState()
                }
                dark.setStroke(); circle.lineWidth = 4; circle.stroke()
            }
            style.setImage(image, forName: id)
        }
        let point = MLNPointFeature(); point.coordinate = coordinate
        let source = MLNShapeSource(identifier: id, shape: point, options: nil)
        style.addSource(source); sources.insert(id)
        let symbol = MLNSymbolStyleLayer(identifier: id, source: source)
        symbol.iconImageName = NSExpression(forConstantValue: id)
        symbol.iconAllowsOverlap = NSExpression(forConstantValue: true)
        symbol.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        style.addLayer(symbol); layers.insert(id)
    }

    private func addPoint(_ coordinate: CLLocationCoordinate2D, id: String, color: UIColor, radius: Double, style: MLNStyle) {
        let point = MLNPointFeature(); point.coordinate = coordinate
        let source = MLNShapeSource(identifier: id, shape: point, options: nil)
        style.addSource(source); sources.insert(id)
        let circle = MLNCircleStyleLayer(identifier: id, source: source)
        circle.circleColor = NSExpression(forConstantValue: color)
        circle.circleRadius = NSExpression(forConstantValue: radius)
        circle.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        circle.circleStrokeWidth = NSExpression(forConstantValue: 2)
        style.addLayer(circle); layers.insert(id)
    }
}

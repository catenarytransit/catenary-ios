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
        let journeys = state.details ? state.itineraries.enumerated().filter { $0.offset == state.selected } : Array(state.itineraries.enumerated())
        var bounds: [CLLocationCoordinate2D] = []
        // Draw selected journey last so its full colour remains visible.
        let ordered = journeys.sorted { ($0.offset == state.selected ? 1 : 0) < ($1.offset == state.selected ? 1 : 0) }
        for (index, journey) in ordered {
            for (legIndex, leg) in journey.legs.enumerated() {
                var coordinates = directionsCoordinates(leg).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                if coordinates.count < 2, let from = leg.from?.location, let to = leg.to?.location {
                    coordinates = [from.coordinate, to.coordinate]
                }
                bounds += coordinates
                guard coordinates.count >= 2 else { continue }
                let id = "planner-\(index)-\(legIndex)"
                let source = MLNShapeSource(identifier: id, shape: MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count)), options: nil)
                style.addSource(source); sources.insert(id)
                let line = MLNLineStyleLayer(identifier: id, source: source)
                line.lineColor = NSExpression(forConstantValue: leg.uiColor)
                line.lineWidth = NSExpression(forConstantValue: index == state.selected ? 6 : 4)
                line.lineOpacity = NSExpression(forConstantValue: index == state.selected ? 1 : 0.35)
                if leg.street { line.lineDashPattern = NSExpression(forConstantValue: [1, 1.5]) }
                style.addLayer(line); layers.insert(id)
                if state.showTransfers, index == state.selected {
                    for (position, point) in [leg.from?.location, leg.to?.location].enumerated() {
                        if let point { addPoint(point.coordinate, id: "\(id)-stop-\(position)", color: .systemGray, radius: 4, style: style) }
                    }
                }
            }
        }
        for (index, point) in [state.origin, state.destination].enumerated() {
            if let point {
                bounds.append(point.coordinate)
                addPoint(point.coordinate, id: "planner-endpoint-\(index)", color: index == 0 ? .systemGreen : .systemPurple, radius: 8, style: style)
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

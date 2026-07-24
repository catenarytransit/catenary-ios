import CoreLocation
import MapLibre
import SwiftUI

/// A map pin that stays anchored to a geographic coordinate and can be dragged
/// to choose a new nearby-departures origin. The conversion uses the current
/// visible map bounds, which keeps the pin in sync while the map pans or zooms.
struct DraggableNearbyPinOverlay: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    let bounds: MLNCoordinateBounds

    @GestureState private var translation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            if let coordinate,
               let anchor = screenPoint(for: coordinate, in: proxy.size) {
                Image(systemName: "mappin.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.red)
                    .font(.system(size: 42, weight: .semibold))
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
                    .contentShape(Circle())
                    .position(
                        x: anchor.x + translation.width,
                        y: anchor.y + translation.height - 18
                    )
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .updating($translation) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                let point = CGPoint(
                                    x: anchor.x + value.translation.width,
                                    y: anchor.y + value.translation.height
                                )
                                if let newCoordinate = mapCoordinate(from: point, in: proxy.size) {
                                    self.coordinate = newCoordinate
                                }
                            }
                    )
                    .accessibilityLabel("Nearby departures location")
                    .accessibilityHint("Drag the pin to choose another location")
            }
        }
        .ignoresSafeArea()
    }

    private func screenPoint(
        for coordinate: CLLocationCoordinate2D,
        in size: CGSize
    ) -> CGPoint? {
        guard size.width > 0, size.height > 0 else { return nil }
        let west = bounds.sw.longitude
        let east = unwrappedEastLongitude(west: west, east: bounds.ne.longitude)
        let longitude = unwrap(coordinate.longitude, relativeTo: west)
        let longitudeSpan = east - west

        let northY = mercatorY(bounds.ne.latitude)
        let southY = mercatorY(bounds.sw.latitude)
        let coordinateY = mercatorY(coordinate.latitude)
        let latitudeSpan = northY - southY

        guard longitudeSpan.isFinite, latitudeSpan.isFinite,
              abs(longitudeSpan) > .ulpOfOne, abs(latitudeSpan) > .ulpOfOne else { return nil }

        return CGPoint(
            x: (longitude - west) / longitudeSpan * size.width,
            y: (northY - coordinateY) / latitudeSpan * size.height
        )
    }

    private func mapCoordinate(from point: CGPoint, in size: CGSize) -> CLLocationCoordinate2D? {
        guard size.width > 0, size.height > 0 else { return nil }
        let clampedX = min(max(point.x, 0), size.width)
        let clampedY = min(max(point.y, 0), size.height)

        let west = bounds.sw.longitude
        let east = unwrappedEastLongitude(west: west, east: bounds.ne.longitude)
        let longitude = west + Double(clampedX / size.width) * (east - west)

        let northY = mercatorY(bounds.ne.latitude)
        let southY = mercatorY(bounds.sw.latitude)
        let projectedY = northY - Double(clampedY / size.height) * (northY - southY)
        let latitude = inverseMercatorY(projectedY)

        guard latitude.isFinite, longitude.isFinite else { return nil }
        return CLLocationCoordinate2D(
            latitude: min(max(latitude, -85.05112878), 85.05112878),
            longitude: normalizedLongitude(longitude)
        )
    }

    private func mercatorY(_ latitude: CLLocationDegrees) -> Double {
        let clamped = min(max(latitude, -85.05112878), 85.05112878)
        let radians = clamped * .pi / 180
        return log(tan(.pi / 4 + radians / 2))
    }

    private func inverseMercatorY(_ value: Double) -> CLLocationDegrees {
        (2 * atan(exp(value)) - .pi / 2) * 180 / .pi
    }

    private func unwrappedEastLongitude(west: Double, east: Double) -> Double {
        east < west ? east + 360 : east
    }

    private func unwrap(_ longitude: Double, relativeTo west: Double) -> Double {
        var value = longitude
        while value < west { value += 360 }
        while value > west + 360 { value -= 360 }
        return value
    }

    private func normalizedLongitude(_ longitude: Double) -> Double {
        var value = longitude
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }
}

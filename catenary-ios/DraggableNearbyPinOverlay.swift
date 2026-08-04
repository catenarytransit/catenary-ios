import CoreLocation
import MapLibre
import SwiftUI
import UIKit

@MainActor
final class NearbyPinMapCoordinator: ObservableObject {
    static let sourceIdentifier = "nearby-pin"
    static let layerIdentifier = "nearby-pin-symbol"

    @Published private(set) var screenPoint: CGPoint?

    private weak var mapView: MLNMapView?
    private var pinActive = false
    private var pinCoordinate: CLLocationCoordinate2D?
    private var contentInset: UIEdgeInsets = .zero
    private var screenPointRefreshScheduled = false

    func install(on mapView: MLNMapView) {
        self.mapView = mapView
        mapView.automaticallyAdjustsContentInset = false
        applyContentInset()
        updatePinSource()
        configurePinLayer()
        scheduleScreenPointRefresh()
    }

    func updatePin(active: Bool, coordinate: CLLocationCoordinate2D?) {
        let changed = pinActive != active || !coordinatesEqual(pinCoordinate, coordinate)
        pinActive = active
        pinCoordinate = coordinate

        guard changed else {
            configurePinLayer()
            return
        }

        updatePinSource()
        scheduleScreenPointRefresh()
    }

    func updateContentInset(_ inset: UIEdgeInsets) {
        guard !insetsEqual(contentInset, inset) else { return }
        contentInset = inset
        applyContentInset()
        scheduleScreenPointRefresh()
    }

    func refreshScreenPoint() {
        configurePinLayer()
        guard pinActive, let pinCoordinate, let mapView else {
            setScreenPoint(nil)
            return
        }

        setScreenPoint(mapView.convert(pinCoordinate, toPointTo: mapView))
    }

    func coordinate(at point: CGPoint) -> CLLocationCoordinate2D? {
        guard let mapView, mapView.bounds.width > 0, mapView.bounds.height > 0 else { return nil }

        let clampedPoint = CGPoint(
            x: min(max(point.x, mapView.bounds.minX), mapView.bounds.maxX),
            y: min(max(point.y, mapView.bounds.minY), mapView.bounds.maxY)
        )
        let coordinate = mapView.convert(clampedPoint, toCoordinateFrom: mapView)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private func applyContentInset() {
        guard let mapView, !insetsEqual(mapView.contentInset, contentInset) else { return }
        mapView.contentInset = contentInset
    }

    private func scheduleScreenPointRefresh() {
        guard !screenPointRefreshScheduled else { return }
        screenPointRefreshScheduled = true

        Task { @MainActor [weak self] in
            // The map-view modifier runs during SwiftUI's update pass. Publish the
            // derived screen point only after that pass has returned.
            await Task.yield()
            guard let self else { return }
            self.screenPointRefreshScheduled = false
            self.refreshScreenPoint()
        }
    }

    private func updatePinSource() {
        guard let source = mapView?.style?.source(
            withIdentifier: Self.sourceIdentifier
        ) as? MLNShapeSource else { return }

        let features: [MLNShape & MLNFeature]
        if pinActive, let pinCoordinate {
            let feature = MLNPointFeature()
            feature.coordinate = pinCoordinate
            features = [feature]
        } else {
            features = []
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func configurePinLayer() {
        guard let layer = mapView?.style?.layer(
            withIdentifier: Self.layerIdentifier
        ) as? MLNSymbolStyleLayer else { return }

        // MapLibreSwiftDSL does not currently expose icon-ignore-placement.
        layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
    }

    private func setScreenPoint(_ point: CGPoint?) {
        switch (screenPoint, point) {
        case (nil, nil):
            return
        case let (current?, next?) where hypot(current.x - next.x, current.y - next.y) < 0.25:
            return
        default:
            screenPoint = point
        }
    }

    private func coordinatesEqual(
        _ lhs: CLLocationCoordinate2D?,
        _ rhs: CLLocationCoordinate2D?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
        default:
            return false
        }
    }

    private func insetsEqual(_ lhs: UIEdgeInsets, _ rhs: UIEdgeInsets) -> Bool {
        lhs.top == rhs.top
            && lhs.left == rhs.left
            && lhs.bottom == rhs.bottom
            && lhs.right == rhs.right
    }
}

/// Gesture-only overlay for the nearby-departures pin. The marker itself is a
/// MapLibre symbol layer; this view only provides the small draggable hitbox and
/// the Android-matching drag halo.
struct DraggableNearbyPinOverlay: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @ObservedObject var mapCoordinator: NearbyPinMapCoordinator

    var markerSize: CGFloat = 40
    var hitSize: CGFloat = 40

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var dragOrigin: CGPoint?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { _ in
            if let anchor = dragOrigin ?? mapCoordinator.screenPoint {
                let visualCenter = CGPoint(
                    x: anchor.x + dragTranslation.width,
                    y: anchor.y + dragTranslation.height
                )

                ZStack {
                    if isDragging {
                        Circle()
                            .fill(Color(red: Double(0x8E) / 255.0, green: Double(0x51) / 255.0, blue: 1.0).opacity(0.8))
                            .frame(width: markerSize * 1.5, height: markerSize * 1.5)
                            .position(visualCenter)
                    }

                    Color.clear
                        .frame(width: hitSize, height: hitSize)
                        .contentShape(Rectangle())
                        .position(visualCenter)
                        .gesture(
                            DragGesture(minimumDistance: 2, coordinateSpace: .local)
                                .updating($dragTranslation) { value, state, _ in
                                    state = value.translation
                                }
                                .onChanged { _ in
                                    if dragOrigin == nil {
                                        dragOrigin = mapCoordinator.screenPoint ?? anchor
                                    }
                                    isDragging = true
                                }
                                .onEnded { value in
                                    let origin = dragOrigin ?? anchor
                                    let finalPoint = CGPoint(
                                        x: origin.x + value.translation.width,
                                        y: origin.y + value.translation.height
                                    )

                                    if let newCoordinate = mapCoordinator.coordinate(at: finalPoint) {
                                        coordinate = newCoordinate
                                    }
                                    dragOrigin = nil
                                    isDragging = false
                                }
                        )
                        .accessibilityLabel("Nearby departures location")
                        .accessibilityHint("Drag the pin to choose another location")
                }
            }
        }
        .ignoresSafeArea()
        .catenaryOnChange(of: dragTranslation) { oldValue, newValue in
            // DragGesture can be cancelled without invoking onEnded.
            if isDragging, oldValue != .zero, newValue == .zero {
                dragOrigin = nil
                isDragging = false
            }
        }
    }
}

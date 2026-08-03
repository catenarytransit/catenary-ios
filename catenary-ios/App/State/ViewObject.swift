//
//  ViewObject.swift
//  catenary-ios
//

import CoreLocation
import Foundation
import MapLibre
import MapLibreSwiftUI
import SwiftUI
import UIKit

private struct PersistedMapCamera {
    let coordinate: CLLocationCoordinate2D
    let zoom: Double
}

private enum MapCameraPersistence {
    private static let latitudeKey = "map.camera.latitude"
    private static let longitudeKey = "map.camera.longitude"
    private static let zoomKey = "map.camera.zoom"

    static func load(defaults: UserDefaults = .standard) -> PersistedMapCamera? {
        guard defaults.object(forKey: latitudeKey) != nil,
              defaults.object(forKey: longitudeKey) != nil,
              defaults.object(forKey: zoomKey) != nil else { return nil }

        let coordinate = CLLocationCoordinate2D(
            latitude: defaults.double(forKey: latitudeKey),
            longitude: defaults.double(forKey: longitudeKey)
        )
        let zoom = defaults.double(forKey: zoomKey)
        guard CLLocationCoordinate2DIsValid(coordinate), zoom.isFinite else { return nil }
        return PersistedMapCamera(coordinate: coordinate, zoom: zoom)
    }

    static func save(
        coordinate: CLLocationCoordinate2D,
        zoom: Double,
        defaults: UserDefaults = .standard
    ) {
        guard CLLocationCoordinate2DIsValid(coordinate), zoom.isFinite else { return }
        defaults.set(coordinate.latitude, forKey: latitudeKey)
        defaults.set(coordinate.longitude, forKey: longitudeKey)
        defaults.set(zoom, forKey: zoomKey)
    }
}

private let persistedMapCameraAtLaunch = MapCameraPersistence.load()

class viewObject: ObservableObject {
    @Published var camera: MapViewCamera = {
        if let saved = persistedMapCameraAtLaunch {
            return .center(saved.coordinate, zoom: saved.zoom)
        }
        return .center(
            CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
            zoom: 5.0
        )
    }()
    private var hasResolvedInitialMapCamera = persistedMapCameraAtLaunch != nil
    @Published private(set) var selectedStopContext: SelectedStopMapContext?

    func setSelectedStopContext(_ context: SelectedStopMapContext) {
        guard selectedStopContext != context else { return }
        selectedStopContext = context
    }

    func clearSelectedStopContext(id: String) {
        guard selectedStopContext?.id == id else { return }
        selectedStopContext = nil
    }

    func useInitialUserLocationIfNeeded(_ coordinate: CLLocationCoordinate2D) {
        guard !hasResolvedInitialMapCamera,
              CLLocationCoordinate2DIsValid(coordinate) else { return }

        let zoom = 13.0
        camera = .center(coordinate, zoom: zoom)
        hasResolvedInitialMapCamera = true
        MapCameraPersistence.save(coordinate: coordinate, zoom: zoom)
    }

    func rememberMapCamera(center: CLLocationCoordinate2D, zoom: Double) {
        guard hasResolvedInitialMapCamera else { return }
        MapCameraPersistence.save(coordinate: center, zoom: zoom)
    }

    @Published var allLayerSettings: AllLayerSettings = LayerSettingsPersistence.load() {
        didSet {
            LayerSettingsPersistence.save(allLayerSettings)
        }
    }
    @Published var currZoom: Double = 5.0
    @Published var visibleCoordinateBounds: MLNCoordinateBounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: 0, longitude: 0), ne: CLLocationCoordinate2D(latitude: 0, longitude: 0))

    @Published var searchText = ""
    @Published var showTopView = false
    @Published var presDetent: PresentationDetent = .height(80)
    @Published var sheetHeight: CGFloat = 350 {
            didSet { checkHeightEquality() }
        }
    @Published var largeDetentHeight: CGFloat = 0
    @Published var currentRotation: CLLocationDirection = 0
    @Published var isSearchFocusing: Bool = false

    /// `true` whenever the map camera is in any user-tracking mode.
    /// Derived from `camera.state`, so it updates automatically when the user
    /// pans the map and MapLibre exits tracking.
    var centered: Bool {
        switch camera.state {
        case .trackingUserLocation,
             .trackingUserLocationWithHeading,
             .trackingUserLocationWithCourse:
            return true
        default:
            return false
        }
    }
    @Published var showLayerSelector: Bool = false
    @Published private(set) var catenaryStack: [CatenaryStackItem] = []

    var currentStackItem: CatenaryStackItem? { catenaryStack.last }

    func push(_ item: CatenaryStackItem) {
        catenaryStack.append(item)
        presDetent = .large
        isSearchFocusing = false
    }

    func replaceTop(with item: CatenaryStackItem) {
        if catenaryStack.isEmpty {
            catenaryStack.append(item)
        } else {
            catenaryStack[catenaryStack.count - 1] = item
        }
        presDetent = .large
    }

    @discardableResult
    func pop() -> CatenaryStackItem? {
        catenaryStack.popLast()
    }

    func home() {
        catenaryStack.removeAll()
        selectedStopContext = nil
        presDetent = .height(350)
    }

    /// Mirrors StopScreen's `updateStackTime`: replace the current destination
    /// instead of pushing another copy, so returning to the screen restores the
    /// selected time slice.
    func updateCurrentStopTime(_ timeEpochSeconds: Int64?) {
        guard let current = currentStackItem else { return }
        switch current {
        case let .stop(chateauID, stopID, oldTime):
            guard oldTime != timeEpochSeconds else { return }
            replaceTop(with: .stop(
                chateauID: chateauID,
                stopID: stopID,
                timeEpochSeconds: timeEpochSeconds
            ))
        case let .osmStation(osmStationID, stationName, modeType, latitude, longitude, oldTime):
            guard oldTime != timeEpochSeconds else { return }
            replaceTop(with: .osmStation(
                osmStationID: osmStationID,
                stationName: stationName,
                modeType: modeType,
                latitude: latitude,
                longitude: longitude,
                timeEpochSeconds: timeEpochSeconds
            ))
        default:
            break
        }
    }

    @Published var confirmedEqual: Bool = false
    private var equalityTimer: Timer?
    private let equalityDuration: TimeInterval = 0.25

    private func checkHeightEquality() {
        if sheetHeight == largeDetentHeight {
            // start or restart the timer
            equalityTimer?.invalidate()
            equalityTimer = Timer.scheduledTimer(withTimeInterval: equalityDuration, repeats: false) { [weak self] _ in
                withAnimation {
                    self?.confirmedEqual = true
                }
            }
        } else {
            // if diiverged: reset
            equalityTimer?.invalidate()
            withAnimation {
                confirmedEqual = false
            }
        }
    }

    deinit {
        equalityTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    @Published var isVisible: Bool = false
    @Published var topHeightKeys: CGFloat = 0
//    @Published var sheetHeight: CGFloat = 0

    init() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isVisible = true
            self?.topHeightKeys = self?.sheetHeight ?? 350
            self?.sheetHeight = self?.largeDetentHeight ?? 350
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isVisible = false
        }
    }

}

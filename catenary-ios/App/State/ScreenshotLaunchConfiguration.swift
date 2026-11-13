//
//  ScreenshotLaunchConfiguration.swift
//  catenary-ios
//

import CoreLocation
import Foundation
import MapLibre

#if DEBUG || SCREENSHOT_AUTOMATION
struct ScreenshotMapCamera {
    let coordinate: CLLocationCoordinate2D
    let zoom: Double
}

enum ScreenshotDrawerState: String {
    case collapsed
    case midway
    case expanded
}

struct ScreenshotLaunchConfiguration {
    static let current = ScreenshotLaunchConfiguration(
        arguments: ProcessInfo.processInfo.arguments
    )

    let userCoordinate: CLLocationCoordinate2D?
    let mapCamera: ScreenshotMapCamera?
    let deepLink: URL?
    let drawerState: ScreenshotDrawerState?
    let readyToken: String?
    // "results" starts a fresh live search; 1...3 reopen that exact saved result set.
    let plannerScreen: String?
    let plannerQueryPath: String?

    init(arguments: [String]) {
        userCoordinate = Self.coordinate(
            from: Self.value(after: "--ci-screenshot-user-location", in: arguments)
        )
        mapCamera = Self.mapCamera(
            from: Self.value(after: "--ci-screenshot-map", in: arguments)
        )
        deepLink = Self.value(after: "--ci-screenshot-deep-link", in: arguments)
            .flatMap { URL(string: $0) }
        plannerQueryPath = Self.value(after: "--ci-screenshot-planner-query", in: arguments)
        plannerScreen = Self.value(after: "--ci-screenshot-planner", in: arguments)
            .flatMap { ["results", "1", "2", "3"].contains($0) ? $0 : nil }
        readyToken = Self.value(after: "--ci-screenshot-ready-token", in: arguments)

        if arguments.contains("--ci-screenshot-drawer-expanded") {
            drawerState = .expanded
        } else if arguments.contains("--ci-screenshot-drawer-collapsed") {
            drawerState = .collapsed
        } else if arguments.contains("--ci-screenshot-drawer-midway") {
            drawerState = .midway
        } else {
            drawerState = Self.value(after: "--ci-screenshot-drawer", in: arguments)
                .flatMap(ScreenshotDrawerState.init(rawValue:))
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }

    private static func coordinate(from value: String?) -> CLLocationCoordinate2D? {
        guard let value else { return nil }
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]) else {
            return nil
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return coordinate
    }

    private static func mapCamera(from value: String?) -> ScreenshotMapCamera? {
        guard let value else { return nil }
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              let zoom = Double(parts[2]),
              zoom.isFinite else {
            return nil
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return ScreenshotMapCamera(coordinate: coordinate, zoom: zoom)
    }
}

final class ScreenshotReadiness {
    static let shared = ScreenshotReadiness()

    private let lock = NSLock()
    private var drawerReady = false
    private var mapReady = false
    private var signalScheduled = false
    private var signalSent = false
    private var plannerStatus = "Waiting for planner"
    private var plannerScrollOffset = 0.0

    func recordPlannerScrollOffset(_ offset: Double) {
        lock.lock()
        plannerScrollOffset = offset
        writeStatusLocked()
        lock.unlock()
    }

    private init() {}

    func failPlanner(_ message: String) {
        guard let token = ScreenshotLaunchConfiguration.current.readyToken else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("catenary-screenshot-error-\(token)")
        try? Data(message.utf8).write(to: url, options: .atomic)
        setPlannerStatus("Failed: \(message)")
    }

    func setPlannerStatus(_ message: String) {
        lock.lock()
        plannerStatus = message
        writeStatusLocked()
        lock.unlock()
    }

    // Called under the readiness lock; the atomic file is read by the CI runner.
    private func writeStatusLocked() {
        guard ScreenshotLaunchConfiguration.current.plannerScreen != nil,
              let token = ScreenshotLaunchConfiguration.current.readyToken else { return }
        let status = "\(plannerStatus)\nplannerScrollOffset=\(plannerScrollOffset)\ndrawerReady=\(drawerReady) mapReady=\(mapReady) signalSent=\(signalSent)\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("catenary-screenshot-status-\(token)")
        try? Data(status.utf8).write(to: url, options: .atomic)
    }

    func markDrawerReady() {
        guard ScreenshotLaunchConfiguration.current.plannerScreen == nil else { return }
        update { drawerReady = true }
    }

    func markPlannerReady() {
        update { drawerReady = true }
    }

    func markMapReady() {
        update { mapReady = true }
    }

    func invalidateMapReady() {
        lock.lock()
        mapReady = false
        writeStatusLocked()
        lock.unlock()
    }

    private func update(_ mutation: () -> Void) {
        guard ScreenshotLaunchConfiguration.current.readyToken != nil else { return }

        lock.lock()
        mutation()
        writeStatusLocked()
        let shouldSchedule = drawerReady && mapReady && !signalScheduled && !signalSent
        if shouldSchedule {
            signalScheduled = true
        }
        lock.unlock()

        guard shouldSchedule else { return }

        // Give SwiftUI one presentation beat after both asynchronous data and
        // MapLibre rendering have completed so the ready marker represents the
        // frame CI is actually about to capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.emitIfStillReady()
        }
    }

    private func emitIfStillReady() {
        lock.lock()
        guard drawerReady, mapReady, !signalSent,
              let token = ScreenshotLaunchConfiguration.current.readyToken else {
            signalScheduled = false
            lock.unlock()
            return
        }
        signalSent = true
        lock.unlock()

        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("catenary-screenshot-ready-\(token)")
        do {
            try Data("SCREENSHOT_READY \(token)\n".utf8)
                .write(to: markerURL, options: .atomic)
            print("SCREENSHOT_READY \(token)")
        } catch {
            print("SCREENSHOT_READY_WRITE_FAILED \(token): \(error)")
        }
    }
}

final class ScreenshotMapRenderObserver: NSObject, MLNMapViewDelegate {
    static let shared = ScreenshotMapRenderObserver()

    private weak var downstream: MLNMapViewDelegate?

    private override init() {
        super.init()
    }

    func install(on mapView: MLNMapView) {
        if let delegate = mapView.delegate, delegate === self {
            return
        }

        downstream = mapView.delegate
        mapView.delegate = self
    }

    func mapViewDidFinishRenderingMap(_ mapView: MLNMapView, fullyRendered: Bool) {
        downstream?.mapViewDidFinishRenderingMap?(mapView, fullyRendered: fullyRendered)
        guard fullyRendered else { return }
        ScreenshotReadiness.shared.markMapReady()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (downstream?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if downstream?.responds(to: aSelector) == true {
            return downstream
        }
        return super.forwardingTarget(for: aSelector)
    }
}

#endif

//
//  ScreenshotLaunchConfiguration.swift
//  catenary-ios
//

import CoreLocation
import Foundation

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

    init(arguments: [String]) {
        userCoordinate = Self.coordinate(
            from: Self.value(after: "--ci-screenshot-user-location", in: arguments)
        )
        mapCamera = Self.mapCamera(
            from: Self.value(after: "--ci-screenshot-map", in: arguments)
        )
        deepLink = Self.value(after: "--ci-screenshot-deep-link", in: arguments)
            .flatMap { URL(string: $0) }

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
#endif

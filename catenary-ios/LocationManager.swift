//
//  LocationManager.swift
//  catenary-ios
//
//

import Foundation
import CoreLocation


final class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    @Published var lastKnownLocation: CLLocationCoordinate2D?
    var manager = CLLocationManager()

    override init() {
        super.init()
#if DEBUG || SCREENSHOT_AUTOMATION
        lastKnownLocation = ScreenshotLaunchConfiguration.current.userCoordinate
#endif
    }

    func checkLocationAuthorization() {
#if DEBUG || SCREENSHOT_AUTOMATION
        if let userCoordinate = ScreenshotLaunchConfiguration.current.userCoordinate {
            lastKnownLocation = userCoordinate
            return
        }
#endif
        manager.delegate = self

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            
        case .restricted:
            print("Location restricted")
            
        case .denied:
            print("Location denied")
            
        case .authorizedAlways, .authorizedWhenInUse:
            print("Location authorized")
            manager.startUpdatingLocation() // <— wait for delegate
            
        @unknown default:
            print("Location service disabled")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location Manager configuration
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        
        lastKnownLocation = locations.first?.coordinate
//        manager.stopUpdatingLocation() // optional: stop after first update
    }
}

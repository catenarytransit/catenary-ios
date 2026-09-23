//
//  AppTrackingSupport.swift
//  catenary-ios
//
//  Created by David Pilarčík on 19.09.2026.
//

// Adapted from - https://stackoverflow.com/a/63624792
// Posted by Mark
// Retrieved 2026-09-19, License - CC BY-SA 4.0

import AppTrackingTransparency

func requestTrackingPermission() {
    ATTrackingManager.requestTrackingAuthorization { status in
        switch status {
        case .authorized:
            print("Authorized")
        case .denied:
            print("Denied")
        case .notDetermined:
            print("Not Determined")
        case .restricted:
            print("Restricted")
        @unknown default:
            print("Unknown")
        }
    }
}

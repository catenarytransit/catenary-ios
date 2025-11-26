//
//  BottomDrawer.swift
//  catenary-ios
//
//


import MapLibre
import MapLibreSwiftDSL
import CoreLocationUI
import SwiftUI
import CoreLocation
import MapLibreSwiftUI

struct BottomDrawer: View {
    @Binding var selectedDetent: PresentationDetent
    @ObservedObject var locationManager: LocationManager
    @EnvironmentObject var viewObject: viewObject
    var body: some View {
        VStack(spacing: 20) {
            Text("Hello World")

//            if let coordinate = locationManager.lastKnownLocation {
//                            Text("Latitude: \(coordinate.latitude)")
//                            
//                            Text("Longitude: \(coordinate.longitude)")
//                        } else {
//                            Text("Unknown Location")
//                        }
            


        }
        .padding()
    }
}

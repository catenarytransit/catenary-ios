//
//  ContentView.swift
//  catenary-ios
//
//

import MapLibre
import MapLibreSwiftDSL
import CoreLocationUI
import SwiftUI
import CoreLocation
import MapLibreSwiftUI

struct mapView: View {
    let styleURL: URL = URL(string: "https://maps.catenarymaps.org/light-style.json")!
    @EnvironmentObject var viewobject: viewObject

    var body: some View {
        MapView(styleURL: styleURL, camera: $viewobject.camera) {
        }
        .ignoresSafeArea()  // if you want full‑screen
    }
}

final class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    
    @Published var lastKnownLocation: CLLocationCoordinate2D?
    var manager = CLLocationManager()
    
    
    func checkLocationAuthorization() {
        
        manager.delegate = self
        manager.startUpdatingLocation()
        
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            
        case .restricted://can't change because of parental controls
            print("Location restricted")
            
        case .denied://denied by user or in airplane mode
            print("Location denied")
            
        case .authorizedAlways://always allowed
            print("Location always authorized")
            
        case .authorizedWhenInUse://only when app open
            print("Location authorized when in use")
            lastKnownLocation = manager.location?.coordinate
            
        @unknown default:
            print("Location service disabled")
        
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        //Trigged when auth status changes
        checkLocationAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastKnownLocation = locations.first?.coordinate
    }
}

struct ContentView: View {
    
    @StateObject var locationManager = LocationManager()

    @State private var isSheetPresented = true
    @State private var selectedDetent: PresentationDetent = .height(80)
    @State private var sheetHeight: CGFloat = 0
    
    var body: some View {
        ZStack {
            mapView()
        }
        .overlay(alignment: .bottomTrailing) {
            floatingToolBar()
                .padding(.trailing, 15)
        }
        .sheet(isPresented: $isSheetPresented) {
            bottomDrawer(selectedDetent: $selectedDetent, locationManager: locationManager)
                .presentationDetents([.height(80), .height(350), .large],
                                     selection: $selectedDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGFloat.self) {
                    max(min($0.size.height, 350), 0)
                } action: { newValue in
                    sheetHeight = newValue
                }
                .ignoresSafeArea()
        }
        
        
        
    }
    @EnvironmentObject var viewobject: viewObject
    @ViewBuilder
    func floatingToolBar() -> some View {
        VStack(spacing: 35) {
            
            Button {
                locationManager.checkLocationAuthorization()
                if let location = locationManager.lastKnownLocation {
                    viewobject.camera.state = .centered(onCoordinate: location, zoom: 15, pitch: 0, pitchRange: .free, direction: CLLocationDirection())
                }
                
//                viewobject.camera.setZoom(2)
//                locationManager.requestLocation()
            } label: {
                Image(systemName: "location")
            }
            
        }
        .font(.title3)
        .foregroundStyle(Color.primary)
        .padding(.vertical, 20)
        .padding(.horizontal, 10)
        .offset(y: -sheetHeight)
        
    }
    
    
}

struct bottomDrawer: View {
    @Binding var selectedDetent: PresentationDetent
    @ObservedObject var locationManager: LocationManager
    var body: some View {
        VStack(spacing: 20) {
            Text("Hello World")
            Text("\(String(describing: selectedDetent))")
                .font(.headline)
            if let coordinate = locationManager.lastKnownLocation {
                            Text("Latitude: \(coordinate.latitude)")
                            
                            Text("Longitude: \(coordinate.longitude)")
                        } else {
                            Text("Unknown Location")
                        }
//
//            Button("Expand to Large") {
//                selectedDetent = .large
//            }
//
//            Button("Collapse to 150pt") {
//                selectedDetent = .height(100)
//            }
        }
        .padding()
    }
}


#Preview {
    ContentView().environmentObject(viewObject())
}

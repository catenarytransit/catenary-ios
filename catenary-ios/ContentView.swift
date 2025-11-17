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

struct ShapeSources {
    static var intercityrailshapes = "https://birch1.catenarymaps.org/shapes_intercity_rail"
    static var localcityrailshapes = "https://birch2.catenarymaps.org/shapes_local_rail"
    static var othershapes = "https://birch3.catenarymaps.org/"
    static var busshapes = URL(string: "https://birch4.catenarymaps.org/shapes_bus")!
}


struct mapView: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    var styleURL: URL {
            URL(string: colorScheme == .light
                ? "https://maps.catenarymaps.org/light-style.json"
                : "https://maps.catenarymaps.org/dark-style.json")!
        }
    @EnvironmentObject var viewobject: viewObject

    var body: some View {
        MapView(styleURL: styleURL, camera: $viewobject.camera) {
                
                let busSource = MLNVectorTileSource(
                    identifier: "buslayer",
                    configurationURL: URL(string: "https://birch4.catenarymaps.org/shapes_bus")!
                )
                

            let lineColorExpression = NSExpression(
                format: "FUNCTION('#', 'stringByAppendingString:', color)"
            )
            
                LineStyleLayer(
                    identifier: "buslayer-line",
                    source: busSource,
                    sourceLayerIdentifier: "data"
                )
                .lineColor(expression: lineColorExpression)
                .lineWidth(2)
                .lineCap(.round)
                .minimumZoomLevel(5)
            
        }
        .ignoresSafeArea()
    }

    
    
}

final class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    @Published var lastKnownLocation: CLLocationCoordinate2D?
    var manager = CLLocationManager()

    func checkLocationAuthorization() {
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
        lastKnownLocation = locations.first?.coordinate
        manager.stopUpdatingLocation() // optional: stop after first update
    }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct ContentView: View {
    
    @StateObject var locationManager = LocationManager()

    @State private var isSheetPresented = true
    @State private var selectedDetent: PresentationDetent = .height(175)
    @State private var sheetHeight: CGFloat = 0
    @State private var locationOpacity: CGFloat = 1
    @State private var animationDuration: CGFloat = 0
    @State private var safeAreaBottomInset: CGFloat = 0
    
    var body: some View {
        ZStack {
            mapView()
        }
        .sheet(isPresented: $isSheetPresented) {
            bottomDrawer(selectedDetent: $selectedDetent, locationManager: locationManager)
                .presentationDetents([.height(175), .height(350), .large],
                                     selection: $selectedDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                .ignoresSafeArea()
                .interactiveDismissDisabled()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { oldValue, newValue in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.25)) {
                        
                        
                        if newValue <= 360 {
                            
                            sheetHeight = newValue
                            
                        } else if newValue < 420 && newValue > 360 {
                            
                            sheetHeight = 350 + ((newValue - 350) / 2)
                            
                        }
                    }
                    
                }
        }
        .overlay(alignment: .bottomTrailing) {
            floatingToolBar()
                .padding(.bottom, 15)
        }
        
        
    }
    @EnvironmentObject var viewobject: viewObject
    @ViewBuilder
    func floatingToolBar() -> some View {
        VStack(spacing: 35) {
            
            Button {
                locationManager.checkLocationAuthorization()
            } label: {
                
                    
                        Image(systemName: "location")
                            .font(.title) // Adjust font size to fit within the circle
                            .foregroundColor(.white)
                            .padding()
                            .background {
                                Circle()
                                    .fill(.blue)
                            }
                
            }
            
        }
        .onChange(of: locationManager.lastKnownLocation) { anOldLocation, newLocation in
            guard let location = newLocation else { return }
            viewobject.camera.state = .centered(
                onCoordinate: location,
                zoom: 15,
                pitch: 0,
                pitchRange: .free,
                direction: CLLocationDirection()
            )
        }
        
        .font(.title3)
        .foregroundStyle(Color.primary)
        
        .padding(.horizontal, 20)
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
            


        }
        .padding()
    }
}


#Preview {
    ContentView().environmentObject(viewObject())
}


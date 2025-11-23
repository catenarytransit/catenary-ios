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
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    var styleURL: URL {
            URL(string: colorScheme == .light
                ? "https://maps.catenarymaps.org/light-style.json"
                : "https://maps.catenarymaps.org/dark-style.json")!
        }
    @EnvironmentObject var viewobject: viewObject
    @State var railInFrame = false
    var body: some View {
        MapView(styleURL: styleURL, camera: $viewobject.camera) {
                // BUS SHAPES LAYER
            let busSource = MLNVectorTileSource(
                identifier: "buslayer",
                configurationURL: ShapeSources.busshapes
            )
                
            let lineColorExpression = NSExpression(
                format: "FUNCTION('#', 'stringByAppendingString:', color)"
            )
            let widthStops = NSExpression(forConstantValue: [
                9:  railInFrame ? 0.3 : 0.4,
                10: railInFrame ? 0.45 : 0.6,
                12: 1.0,
                14: 2.6
            ])
            let opacityStops = NSExpression(forConstantValue: [
                7:  railInFrame ? 0.04 : 0.09,
                8:  railInFrame ? 0.04 : 0.15,
                11: railInFrame ? 0.15 : 0.30,
                14: railInFrame ? 0.20 : 0.30,
                16: railInFrame ? 0.30 : 0.30
            ])
            
                LineStyleLayer(identifier: LayersPerCategory.Bus.Shapes, source: busSource, sourceLayerIdentifier: "data")
                .lineColor(expression: lineColorExpression)
                .lineWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: widthStops)
                .lineOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: opacityStops)
                .minimumZoomLevel(railInFrame ? 9 : 8)
                .visible(viewobject.allLayerSettings.bus.shapes)
            
                // BUS SYMBOL LAYER
            
            let lineTextColorExpression = NSExpression(
                format: "FUNCTION('#', 'stringByAppendingString:', text_color)"
            )
            
            let busTextSizeStops = NSExpression(forConstantValue: [
                10: 0.3125,
                11: 0.4375,
                13: 0.625
            ])
            
            if viewobject.tempShow {
                SymbolStyleLayer(identifier: LayersPerCategory.Bus.LabelShapes, source: busSource, sourceLayerIdentifier: "data")
//                    .renderAbove(LayerReferenceAbove.all)
                    .textFontNames(["Barlow-Regular"])
                    .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: busTextSizeStops)
                    .text(expression: NSExpression(format: "route_label"))
                    

            }
            
                
                

                
            
//                .textFontNames(["Barlow-Regular"])
//                .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: busTextSizeStops)
                
            
            
//            SymbolStyleLayer(
//                identifier: LayersPerCategory.Bus.LabelShapes,
//                source: busSource,
//                sourceLayerIdentifier: "data"
//            )
//            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: busTextSizeStops)
////            .iconColor(expression: lineTextColorExpression)
//            .textFontNames(["Barlow-Regular"])
//            .text(expression: NSExpression(forConstantValue: "erm"))
//            .textAllowsOverlap(false)
//            .textColor(expression: lineTextColorExpression)
////            .textAnchor("center")
//            .textHaloColor(expression: lineColorExpression)
//            .textHaloWidth(0.2)
//            .textHaloBlur(0)
//            .minimumZoomLevel(railInFrame ? 13 : 11)
//            .visible(viewobject.allLayerSettings.bus.labelshapes)
            
            
//            .maximumTextWidth(interpolatedBy: <#T##MLNVariableExpression#>, curveType: <#T##MLNExpressionInterpolationMode#>, parameters: <#T##NSExpression?#>, stops: <#T##NSExpression#>)
            
            
            
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
    @EnvironmentObject var viewObject: viewObject
    var body: some View {
        VStack(spacing: 20) {
            Text("Hello World")
            Text("\(String(describing: selectedDetent))")
                .font(.headline)
            Toggle(isOn: $viewObject.tempShow, label: {
                Text("Is on? \(viewObject.tempShow)")
            })
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


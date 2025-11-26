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
            
            let otherShapesSource = MLNVectorTileSource(
                identifier: "otherlayer",
                configurationURL: ShapeSources.othershapes
            )
            
            let intercityRailSource = MLNVectorTileSource(
                identifier: "intercityraillayer",
                configurationURL: ShapeSources.intercityrailshapes
            )
            
            let localCityRailSource = MLNVectorTileSource(
                identifier: "localcityraillayer",
                configurationURL: ShapeSources.localcityrailshapes
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
       

                SymbolStyleLayer(identifier: LayersPerCategory.Bus.LabelShapes, source: busSource, sourceLayerIdentifier: "data")
                .text(expression: NSExpression(format: "route_label"))
                .textColor(expression: lineTextColorExpression)
                .renderAbove(.all)
                .symbolPlacement("line")
                .symbolSpacing(250)
                .textFontSize(4)
                .textHaloBlur(0)
                .textHaloWidth(2)
                .textHaloColor(expression: lineColorExpression)
                .textAllowsOverlap(false)
                .textFontNames(["Barlow-Regular"])
                .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [11: 7, 13: 9]))
                .minimumZoomLevel(railInFrame ? 13 : 11)
                .visible(viewobject.allLayerSettings.bus.labelshapes)
         
            // OTHER (othershapes)

            
            // not( chateau == 'schweiz' AND stop_to_stop_generated == true ) AND (route_type == 6 OR route_type == 7)
            LineStyleLayer(
                         identifier: LayersPerCategory.Other.Shapes,
                         source: otherShapesSource,
                         sourceLayerIdentifier: "data")
            .lineColor(.black)
            .lineColor(expression: lineColorExpression)
            .lineWidth(interpolatedBy: .zoomLevel,
                         curveType: .linear,
                         parameters: nil,
                         stops: NSExpression(forConstantValue: [7: 2.0, 9: 3.0]))
            .lineOpacity(interpolatedBy: .zoomLevel,
                         curveType: .linear,
                         parameters: nil,
                         stops: NSExpression(forConstantValue: [0: 1.0]))
            .minimumZoomLevel(1)
            .visible(viewobject.allLayerSettings.other.shapes)
            .predicate(NSPredicate(format: "NOT ((chateau == %@) AND (stop_to_stop_generated == %@)) AND (route_type == 6 OR route_type == 7)", "schweiz", NSNumber(value: true))) //TODO: make sure this works ?? More of a guess
            
            LineStyleLayer (
                         identifier: LayersPerCategory.Other.FerryShapes,
                         source: otherShapesSource,
                         sourceLayerIdentifier: "data")
            .lineColor(expression: lineColorExpression)
            .lineWidth(interpolatedBy: .zoomLevel,
                         curveType: .linear,
                         parameters: nil,
                         stops: NSExpression(forConstantValue: [6: 0.5, 7: 1.0, 10: 1.5, 14: 3.0]))
            .lineOpacity(interpolatedBy: .zoomLevel,
                         curveType: .linear,
                         parameters: nil,
                         stops: NSExpression(forConstantValue: [6: 0.8, 7: 0.9]))
            .minimumZoomLevel(3)
            .visible(viewobject.allLayerSettings.other.shapes)
            .predicate(NSPredicate(format: "route_type == 4"))
            .lineDashPattern([1,2])
            
            SymbolStyleLayer(
                         identifier: LayersPerCategory.Other.LabelShapes,
                         source: otherShapesSource,
                         sourceLayerIdentifier: "data")
            .symbolPlacement("line")
            .text(expression: NSExpression(format: "route_label"))
            .textFontNames(["Barlow-Regular"])
            .textFontSize(interpolatedBy: .zoomLevel,
                          curveType: .linear,
                          parameters: nil,
                          stops: NSExpression(forConstantValue: [3: 7, 9: 9, 13: 11]))
            .textAllowsOverlap(false)
            .textColor(expression: lineTextColorExpression)
            .textHaloColor(expression: lineColorExpression)
            .textHaloWidth(2)
            .textHaloBlur(1)
            .minimumZoomLevel(3)
            .visible(viewobject.allLayerSettings.other.labelshapes)
            .predicate(NSPredicate(format: "((route_type == 4) OR (route_type == 6) OR (route_type == 7)) AND NOT (chateau == %@ AND stop_to_stop_generated == YES)", "schweiz"))

            /// ========================
            /// INTERCITY RAIL !! (intercityrailshapes) (i don't know, i'm just copying the kotlin page)
            /// ========================
            
            //shapes
            
            
            LineStyleLayer(
                         identifier: LayersPerCategory.IntercityRail.Shapes,
                         source: intercityRailSource,
                         sourceLayerIdentifier: "data")
            .lineColor(expression: lineColorExpression)
            .lineWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [3: 0.4, 5: 0.7, 7: 1.0, 9: 2.0, 11: 2.5]))
            .lineOpacity(expression: NSExpression(forMLNConditional: NSPredicate(format: "stop_to_stop_generated == YES"), trueExpression: NSExpression(forConstantValue: 0.2), falseExpression: NSExpression(forConstantValue: 0.9)))
            .minimumZoomLevel(2)
            .visible(viewobject.allLayerSettings.intercityrail.shapes)
            .predicate(NSPredicate(format: "route_type == 2"))
            
            SymbolStyleLayer(
                         identifier: LayersPerCategory.IntercityRail.LabelShapes,
                         source: intercityRailSource,
                         sourceLayerIdentifier: "data")
            .symbolPlacement("line")
            .symbolSpacing(500)
            .text(expression: NSExpression(format: "route_label"))
            .textFontNames(["Barlow-Bold"])
            .textFontSize(interpolatedBy: .zoomLevel,
                         curveType: .linear,
                         parameters: nil,
                         stops: NSExpression(forConstantValue: [3: 6, 6: 7, 9: 9, 13: 11]))
            .textAllowsOverlap(false)
            .textColor(expression: lineTextColorExpression)
            .textHaloColor(expression: lineColorExpression)
            .textHaloWidth(1)
            .textHaloBlur(1)
            .minimumZoomLevel(5.5)
            .visible(viewobject.allLayerSettings.intercityrail.labelshapes)
            .predicate(NSPredicate(format: "route_type == 2"))
                         
            /// METRO
            
            LineStyleLayer(
                         identifier: LayersPerCategory.Metro.Shapes,
                         source: localCityRailSource,
                         sourceLayerIdentifier: "data")
            .lineColor(expression: lineColorExpression)
            .lineWidth(interpolatedBy: .zoomLevel,
                         curveType: .linear,
                         parameters: nil,
                         stops: NSExpression(forConstantValue: [6: 0.5, 7: 1, 9: 2]))
            .lineOpacity(1)
            .minimumZoomLevel(5)
            .visible(viewobject.allLayerSettings.localrail.shapes)
            .predicate(NSPredicate(format: "(NOT (chateau == 'nyct' OR stop_to_stop_generated == TRUE)) AND (route_type == 1 OR route_type == 12)"))
            
            SymbolStyleLayer(
                         identifier: LayersPerCategory.Metro.LabelShapes,
                         source: localCityRailSource,
                         sourceLayerIdentifier: "data")
            .symbolPlacement("line")
            .symbolSpacing(200)
            .text(expression: NSExpression(format: "route_label"))
            .textFontNames(["Barlow-Bold"])
            .textFontSize(interpolatedBy: .zoomLevel,
                         curveType: .linear,
                         parameters: nil,
                         stops: NSExpression(forConstantValue: [3: 7, 9: 9, 13: 11]))
            .textAllowsOverlap(false)
            //TODO: textpitchalignment necessary? ig same for ignoreplacement
            .textColor(expression: lineTextColorExpression)
            .textHaloColor(expression: lineColorExpression)
            .textHaloWidth(1)
            .textHaloBlur(1)
            .minimumZoomLevel(6)
            .visible(viewobject.allLayerSettings.localrail.labelshapes)
            .predicate(NSPredicate(format: "(NOT (chateau == 'nyct' OR stop_to_stop_generated == TRUE)) AND (route_type == 1 OR route_type == 12)"))
            
            ///TRAM: types 0 & 5, it seems
            ///(route_type == 0 OR route_type == 5) AND (NOT (chateau == 'nyct' OR stop_to_stop_generated == TRUE))
            
            LineStyleLayer(
                         identifier: LayersPerCategory.Tram.Shapes,
                         source: localCityRailSource,
                         sourceLayerIdentifier: "data")
            .lineColor(expression: lineColorExpression)
            .lineWidth(interpolatedBy: .zoomLevel,
                         curveType: .linear,
                         parameters: nil,
                         stops: NSExpression(forConstantValue: [6: 0.5, 7: 1, 9: 2]))
            .lineOpacity(1)
            .minimumZoomLevel(5)
            .visible(viewobject.allLayerSettings.localrail.shapes)
            .predicate(NSPredicate(format: "(route_type == 0 OR route_type == 5) AND (NOT (chateau == 'nyct' OR stop_to_stop_generated == TRUE))"))
            
            SymbolStyleLayer(
                         identifier: LayersPerCategory.Tram.LabelShapes,
                         source: localCityRailSource,
                         sourceLayerIdentifier: "data")
            .symbolPlacement("line")
            .text(expression: NSExpression(format: "route_label"))
            .textFontNames(["Barlow-Medium"])
            .textFontSize(interpolatedBy: .zoomLevel,
                         curveType: .linear,
                         parameters: nil,
                         stops: NSExpression(forConstantValue: [3: 7, 9: 9, 13: 11]))
            .textAllowsOverlap(false)
            .textColor(expression: lineTextColorExpression)
            .textHaloColor(expression: lineColorExpression)
            .textHaloWidth(1)
            .textHaloBlur(1)
            .minimumZoomLevel(6)
            .visible(viewobject.allLayerSettings.localrail.labelshapes)
            .predicate(NSPredicate(format: "(route_type == 0 OR route_type == 5) AND (NOT (chateau == 'nyct' OR stop_to_stop_generated == TRUE))"))
            
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


#Preview {
    ContentView().environmentObject(viewObject())
}


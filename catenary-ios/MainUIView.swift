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

final class FloatingWindow: UIWindow {
    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        self.windowLevel = .statusBar + 5   // ↑ above sheets
        self.backgroundColor = .clear
        self.isHidden = false
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
}


struct MainUIView: View {
    
    @StateObject var locationManager = LocationManager()

    @State private var isSheetPresented = true
//    @State private var selectedDetent: PresentationDetent = .height(80)
    @State private var sheetHeight: CGFloat = 350
    @State private var newValVal: CGFloat = 0
    @State private var locationOpacity: CGFloat = 1
    @State private var animationDuration: CGFloat = 0
    @State private var text = ""
    
    var body: some View {
        ZStack {
            mapLibreView(locationManager: locationManager)
                .sheet(isPresented: $isSheetPresented) {
                    BottomDrawer(selectedDetent: $viewobject.presDetent, locationManager: locationManager)
                        .presentationDetents([.height(80), .height(350), .large], selection: $viewobject.presDetent)
                        
                        .presentationBackgroundInteraction(.enabled)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        .ignoresSafeArea()
                        .interactiveDismissDisabled()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { newValue in
                            viewobject.sheetHeight = newValue
                        }
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            max(min(proxy.size.height, 400), 0)
                        } action: { oldValue, newValue in
                            sheetHeight = min(newValue, 350)
                            if newValue > 350 {
                                viewobject.showTopView = true
                            } else {
                                viewobject.showTopView = false
                            }
                            let progress = max(min((newValue - (350)) / 50, 1), 0)
                            let toolbarOpacity = 1 - progress
                            locationOpacity = toolbarOpacity
                            
                            let diff = abs(newValue - oldValue)
                            let duration = max(min(diff / 100, 0.3), 0)
                            animationDuration = duration
                        }
                }
                .overlay(alignment: .bottomTrailing) {
                    floatingToolBar()
                        .padding(.trailing, 15)
                }
                .overlay(alignment: .top) {
                    if viewobject.sheetHeight < 400 {
                        TextField("Search Here", text: $viewobject.searchText)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .glassEffect(.regular, in: .capsule)
                            .padding()
                            .ignoresSafeArea(.container, edges: .bottom)
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    }
                }

        }
        
        
        
        
        
        
    }
    @EnvironmentObject var viewobject: viewObject
    
    @ViewBuilder
    func floatingToolBar() -> some View {
        VStack {
            if viewobject.currentRotation != 0 {
                Button {
                    //                locationManager.checkLocationAuthorization()
                    viewobject.camera.setDirection(0)
                } label: {
                    Image(systemName: "location.north.line")
                        .rotationEffect(Angle(degrees: viewobject.currentRotation))
                        .padding()
                        .glassEffect(.clear, in: .circle)
                }
                .transition(.opacity.combined(with: .scale))
                .foregroundStyle(Color.primary)
            }
            VStack(spacing: 35) {
                
                Button {
                    //                locationManager.checkLocationAuthorization()
//                    viewobject.camera.setDirection(0)
                    viewobject.showLayerSelector.toggle()
                } label: {
                    Image(systemName: "square.2.layers.3d.fill")
                }
                
                Button {
                    locationManager.checkLocationAuthorization()
                } label: {
                    Image(systemName: "location\(viewobject.centered ? ".fill" : "")")
                }
                
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
            .glassEffect(.regular, in: .capsule)
            
        }
        .font(.title3)
        .offset(y: -sheetHeight)
        .opacity(locationOpacity)
        .animation(.interpolatingSpring(duration: animationDuration, bounce: 0, initialVelocity: 0), value: sheetHeight)
        
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
        
        
    }
    
    
}




#Preview {
    MainUIView().environmentObject(viewObject())
}

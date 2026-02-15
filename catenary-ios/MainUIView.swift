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
    @FocusState var focus: Bool
    @FocusState var isFocused: Bool
    @State private var isSheetPresented = true
//    @State private var selectedDetent: PresentationDetent = .height(80)
    @State private var sheetHeight: CGFloat = 350
    @State private var newValVal: CGFloat = 0
    @State private var locationOpacity: CGFloat = 1
    @State private var animationDuration: CGFloat = 0
    @State private var text = ""
    @State var tempSheetOpacity: CGFloat = 0
    
    
    var body: some View {
        ZStack {
            mapLibreView(locationManager: locationManager)
                .sheet(isPresented: $isSheetPresented) {
                    BottomDrawer(selectedDetent: $viewobject.presDetent, locationManager: locationManager)
                        .ignoresSafeArea(.keyboard)
                        .presentationDetents([.height(80), .height(350), .large], selection: $viewobject.presDetent)
                        
                        .presentationBackgroundInteraction(.enabled)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        .ignoresSafeArea()
                        .interactiveDismissDisabled()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { oldValue, newValue in
                            if viewobject.isVisible {
                                let raisedHeight = newValue + (viewobject.largeDetentHeight - viewobject.topHeightKeys)
                                                               
                                viewobject.sheetHeight = viewobject.largeDetentHeight <= raisedHeight ? viewobject.largeDetentHeight : raisedHeight
                                
                                if viewobject.largeDetentHeight != viewobject.sheetHeight {
                                    withAnimation {
                                        viewobject.isVisible = false
                                    }
                                }
                            } else {
                                
                                viewobject.sheetHeight = newValue 
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            
                            return max(min(proxy.size.height, 450), 0)
                            
                            
                        } action: { oldValue, newValue in
                            
                                print(newValue, isSheetPresented)
                                
                                sheetHeight = min(newValue, 350)
                                if newValue > 400 {
                                    viewobject.showTopView = true
                                } else {
                                    viewobject.showTopView = false
                                }
                                let progress = max(min((newValue - (400)) / 50, 1), 0)
                                let toolbarOpacity = 1 - progress
                                locationOpacity = toolbarOpacity
                                
                                let diff = abs(newValue - oldValue)
                                let duration = max(min(diff / 100, 0.3), 0)
                                animationDuration = duration
                            
                        }
                }
                
                .onChange(of: viewobject.showLayerSelector) { last, current in
                    withAnimation(.bouncy) {
                        if current {
                            isSheetPresented = false
                        } else {
                            isSheetPresented = true
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSheetPresented {
                        floatingToolBar()
                            .padding(.trailing, 15)
                            .transition(.move(edge: .trailing))
                    }
                }
                .overlay(alignment: .top) {
                    if viewobject.sheetHeight < 450 {
                        TextField("Search Here", text: $viewobject.searchText)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .padding()
                            .ignoresSafeArea(.container, edges: .bottom)
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                            .focused($focus)
                        
                            
                    }
                }
                .onChange(of: focus) { from, to in
                    guard to else { return }
                    viewobject.presDetent = .large
                    viewobject.isSearchFocusing = true
                }
//            if presentation detent switches to large & issearch focusing is true, switch focus state to true

        }
        
        
        
        
        
        
    }
    @EnvironmentObject var viewobject: viewObject
    
    @ViewBuilder
    func floatingToolBar() -> some View {
        GlassEffectContainer {
            VStack {
                if viewobject.currentRotation != 0 {
                    Button {
                        //                locationManager.checkLocationAuthorization()
                        viewobject.camera.setDirection(0)
                    } label: {
                        Image(systemName: "location.north.line")
                            .rotationEffect(Angle(degrees: viewobject.currentRotation))
                            .padding()
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .transition(.opacity.combined(with: .scale))
                    .foregroundStyle(Color.primary)
                }
                VStack {
                    
                    Button {
                        //                locationManager.checkLocationAuthorization()
                        //                    viewobject.camera.setDirection(0)
                        viewobject.showLayerSelector.toggle()
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                    }
                    .padding(.bottom)
                    Button {
                        locationManager.checkLocationAuthorization()
                    } label: {
                        Image(systemName: "location\(viewobject.centered ? ".fill" : "")")
                    }
                    .padding(.top)
                    
                }
                .padding(.all, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
                
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
    
    
}




#Preview {
    MainUIView().environmentObject(viewObject())
}

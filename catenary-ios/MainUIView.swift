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
import UIKit

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
    @StateObject private var searchViewModel = SearchViewModel()
    @StateObject private var nearbyPinMapCoordinator = NearbyPinMapCoordinator()
    @FocusState var focus: Bool
    @State private var isSheetPresented = true
//    @State private var selectedDetent: PresentationDetent = .height(80)
    @State private var sheetHeight: CGFloat = 350
    @State private var newValVal: CGFloat = 0
    @State private var locationOpacity: CGFloat = 1
    @State private var animationDuration: CGFloat = 0
    @State private var text = ""
    @State var tempSheetOpacity: CGFloat = 0
    @State private var nearbyPinActive = false
    @State private var nearbyPinCoordinate: CLLocationCoordinate2D?
    @State private var mapViewportSize: CGSize = .zero
    
    
    var body: some View {
        ZStack {
            mapLibreView(
                locationManager: locationManager,
                nearbyPinMapCoordinator: nearbyPinMapCoordinator,
                nearbyPinActive: nearbyPinActive,
                nearbyPinCoordinate: nearbyPinCoordinate,
                contentInset: mapContentInset
            )
                .onOpenURL { url in
                    viewobject.openDeepLink(url)
                    isSheetPresented = true
                }
                .onChange(of: viewobject.catenaryStack) { _, stack in
                    guard !stack.isEmpty else { return }
                    isSheetPresented = true
                    if viewobject.presDetent != .large {
                        viewobject.presDetent = .large
                    }
                    focus = false
                }
                .sheet(isPresented: $isSheetPresented) {
                    BottomDrawer(
                        selectedDetent: $viewobject.presDetent,
                        locationManager: locationManager,
                        searchViewModel: searchViewModel,
                        nearbyPinActive: $nearbyPinActive,
                        nearbyPinCoordinate: $nearbyPinCoordinate
                    )
                        .ignoresSafeArea(.keyboard)
                        .presentationDetents([.height(80), .height(350), .large], selection: $viewobject.presDetent)
                        
                        .presentationBackgroundInteraction(.enabled)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        .ignoresSafeArea(.container, edges: .bottom)
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
                .overlay {
                    if nearbyPinActive, nearbyPinCoordinate != nil {
                        DraggableNearbyPinOverlay(
                            coordinate: $nearbyPinCoordinate,
                            mapCoordinator: nearbyPinMapCoordinator
                        )
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
                        CatenarySearchBar(
                            query: $viewobject.searchText,
                            focus: $focus,
                            onSettingsClick: {
                                focus = false
                                viewobject.searchText = ""
                                viewobject.push(.settings)
                            }
                        )
                        .padding()
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    }
                }
                .onChange(of: focus) { _, isFocused in
                    if isFocused {
                        viewobject.presDetent = .large
                        viewobject.isSearchFocusing = true
                    }
                }
                .onChange(of: viewobject.searchText) { _, query in
                    searchViewModel.search(
                        query: query,
                        userLocation: locationManager.lastKnownLocation,
                        mapCenter: viewobject.visibleCoordinateBounds.catenarySearchCenter
                    )
                }
//            if presentation detent switches to large & issearch focusing is true, switch focus state to true

        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { _, newSize in
            mapViewportSize = newSize
        }
        .task {
            locationManager.checkLocationAuthorization()
            useInitialUserLocationIfNeeded()
        }
        .onChange(of: locationManager.lastKnownLocation?.latitude) { _, _ in
            useInitialUserLocationIfNeeded()
        }
        .onChange(of: locationManager.lastKnownLocation?.longitude) { _, _ in
            useInitialUserLocationIfNeeded()
        }
    }
    @EnvironmentObject var viewobject: viewObject

    private func useInitialUserLocationIfNeeded() {
        guard let coordinate = locationManager.lastKnownLocation else { return }
        viewobject.useInitialUserLocationIfNeeded(coordinate)
    }

    private var mapContentInset: UIEdgeInsets {
        guard isSheetPresented, mapViewportSize.height > 0 else { return .zero }
        guard viewobject.sheetHeight >= mapViewportSize.height / 2 else { return .zero }

        return UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: mapViewportSize.height / 2,
            right: 0
        )
    }
    
    @ViewBuilder
    func floatingToolBar() -> some View {
        Group {
            VStack {
                if viewobject.currentRotation != 0 {
                    Button {
                        //                locationManager.checkLocationAuthorization()
                        viewobject.camera.setDirection(0)
                    } label: {
                        Image(systemName: "location.north.line")
                            .rotationEffect(Angle(degrees: viewobject.currentRotation))
                            .padding()
                            .background(.regularMaterial, in: Circle())
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
                        viewobject.camera = .trackUserLocation(zoom: 15)
                    } label: {
                        Image(systemName: "location\(viewobject.centered ? ".fill" : "")")
                    }
                    .padding(.top)
                    
                }
                .padding(.all, 10)
                .background(.regularMaterial, in: Capsule())
                
            }
            .font(.title3)
            .offset(y: -sheetHeight)
            .opacity(locationOpacity)
            .animation(.interpolatingSpring(duration: animationDuration, bounce: 0, initialVelocity: 0), value: sheetHeight)
        }
        
    }
    
    
}




#Preview {
    MainUIView().environmentObject(viewObject())
}

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
    let searchViewModel: SearchViewModel

    @StateObject var locationManager = LocationManager()
    @StateObject private var nearbyPinMapCoordinator = NearbyPinMapCoordinator()
    @State private var isSheetPresented = true
    @State private var liveSheetHeight: CGFloat = 350
    @State private var locationOpacity: CGFloat = 1
    @State private var text = ""
    @State var tempSheetOpacity: CGFloat = 0
    @State private var nearbyPinActive = false
    @State private var nearbyPinCoordinate: CLLocationCoordinate2D?
    @State private var mapViewportSize: CGSize = .zero
    @State private var mapCameraRevision: UInt64 = 0
    @State private var searchFocusRequest = 0
    
    
    var body: some View {
        ZStack {
            mapLibreView(
                locationManager: locationManager,
                nearbyPinMapCoordinator: nearbyPinMapCoordinator,
                nearbyPinActive: nearbyPinActive,
                nearbyPinCoordinate: nearbyPinCoordinate,
                contentInset: mapContentInset,
                camera: $viewobject.camera,
                cameraRevision: mapCameraRevision,
                layerSettings: viewobject.allLayerSettings,
                selectedStopContext: viewobject.selectedStopContext,
                viewobject: viewobject
            )
                .equatable()
                .onChange(of: viewobject.camera) { _, camera in
                    guard camera.lastReasonForChange == nil
                            || camera.lastReasonForChange == .programmatic else {
                        return
                    }
                    mapCameraRevision &+= 1
                }
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
                }
                .sheet(isPresented: $isSheetPresented) {
                    BottomDrawer(
                        selectedDetent: $viewobject.presDetent,
                        sheetHeight: liveSheetHeight,
                        locationManager: locationManager,
                        searchViewModel: searchViewModel,
                        focusRequest: searchFocusRequest,
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
                            max(proxy.size.height, 0)
                        } action: { _, newValue in
                            let maximumHeight = viewobject.largeDetentHeight > 0
                                ? viewobject.largeDetentHeight
                                : newValue
                            let boundedHeight = min(newValue, maximumHeight)
                            if abs(liveSheetHeight - boundedHeight) > 0.5 {
                                liveSheetHeight = boundedHeight
                            }


                            let progress = max(min((newValue - 400) / 50, 1), 0)
                            let toolbarOpacity = 1 - progress
                            if abs(locationOpacity - toolbarOpacity) > 0.005 {
                                locationOpacity = toolbarOpacity
                            }
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
                    if isSheetPresented,
                       viewobject.currentStackItem == nil,
                       viewobject.presDetent != .large {
                        SearchLauncher(
                            onSearch: beginSearch,
                            onSettingsClick: { viewobject.push(.settings) }
                        )
                        .padding()
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(.opacity)
                    }
                }

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

    private func beginSearch() {
        guard viewobject.currentStackItem == nil else { return }
        viewobject.presDetent = .large
        searchFocusRequest &+= 1
    }

    private func useInitialUserLocationIfNeeded() {
        guard let coordinate = locationManager.lastKnownLocation else { return }
        viewobject.useInitialUserLocationIfNeeded(coordinate)
    }

    private var mapContentInset: UIEdgeInsets {
        guard isSheetPresented, mapViewportSize.height > 0 else { return .zero }
        guard viewobject.presDetent == .large else { return .zero }

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
            .offset(y: -min(liveSheetHeight, 350))
            .opacity(locationOpacity)
        }
        
    }
    
    
}




#Preview {
    MainUIView(searchViewModel: SearchViewModel()).environmentObject(viewObject())
}

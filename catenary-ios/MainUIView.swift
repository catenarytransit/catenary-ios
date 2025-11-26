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

struct MainUIView: View {
    
    @StateObject var locationManager = LocationManager()

    @State private var isSheetPresented = true
    @State private var selectedDetent: PresentationDetent = .height(175)
    @State private var sheetHeight: CGFloat = 0
    @State private var locationOpacity: CGFloat = 1
    @State private var animationDuration: CGFloat = 0
    @State private var safeAreaBottomInset: CGFloat = 0
    
    var body: some View {
        ZStack {
            mapLibreView()
        }
        .sheet(isPresented: $isSheetPresented) {
            BottomDrawer(selectedDetent: $selectedDetent, locationManager: locationManager)
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




#Preview {
    MainUIView().environmentObject(viewObject())
}


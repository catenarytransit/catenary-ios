//
//  catenary_iosApp.swift
//  catenary-ios
//
//

import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

@main
struct CatenaryMapsApp: App {
    @StateObject var viewobject = viewObject()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewobject)
        }
    }
}

class viewObject: ObservableObject {
    @Published var camera: MapViewCamera = MapViewCamera.center(CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), zoom: 5.0)
}

//#Preview {
//    CatenaryMapsApp()
//}

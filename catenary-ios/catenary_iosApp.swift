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

//#Preview {
//    CatenaryMapsApp()
//}

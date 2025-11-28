//
//  BottomDrawer.swift
//  catenary-ios
//
//


import MapLibre
import MapLibreSwiftDSL
import CoreLocationUI
import SwiftUI
import CoreLocation
import MapLibreSwiftUI

struct BottomDrawer: View {
    @Binding var selectedDetent: PresentationDetent
    @ObservedObject var locationManager: LocationManager
    @EnvironmentObject var viewObject: viewObject
    @FocusState var isFocused: Bool
    @State var searchText = ""
    var body: some View {
        VStack {
            ScrollView(.vertical) {
               Text("These are words that we are seeing")
                Text("These are words that we are seeing")
                Text("These are words that we are seeing")
                Text("These are words that we are seeing")
                Text("These are words that we are seeing")
                Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
                 Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
                  Text("These are words that we are seeing")
            }
            .safeAreaInset(edge: .top, spacing: 10) {
                if viewObject.confirmedEqual {

                HStack(spacing: 10) {
                    
                        TextField("Search Here", text: $viewObject.searchText)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.gray.opacity(0.25), in: .capsule)
                            .focused($isFocused)
                            .transition(.blurReplace)
//                            .shadow(color: .black.opacity(0.1), radius: 3)
                    }
                    
                .padding(.horizontal, 18)
                .frame(height: 80)
                }
                
//                .padding(.top, 5)
                
            }
        }
        
        
        
    }
}

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
    @State var keepAlive: Bool = false
    
    var body: some View {
        VStack {
            ScrollView(.vertical) {
                //                VStack {
                //                    HStack {
                //                        Spacer()
                //                    }
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                    Text("These are words that we are seeing")
                //                }
                //            }
                
                
                if viewObject.confirmedEqual {
                    Text("\(viewObject.sheetHeight), \(viewObject.largeDetentHeight)")
                    Text("hey this is confirmd to be equal lol")
                    
                } else {
                    Text("\(viewObject.sheetHeight), \(viewObject.largeDetentHeight)")
                }
                Text("i focused: \(isFocused ? "true" : "false")")
                Text("keyoard visible? \(viewObject.isVisible ? "true" : "false")")
                Spacer()
            }
        }
            .safeAreaBar(edge: .top) {
                VStack {
                    if viewObject.confirmedEqual || viewObject.isVisible {
                        
                        HStack(spacing: 10) {
                            
                            TextField("Search Here", text: $viewObject.searchText)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.gray.opacity(0.25), in: .capsule)
                                .focused($isFocused)
                                .transition(.blurReplace)
                                .glassEffect(.regular.interactive(), in: .capsule)
                                

                            //                            .shadow(color: .black.opacity(0.1), radius: 3)
                        }
                        
                        .padding(.horizontal, 18)
                        .frame(height: 80)
                    } else {
                        if selectedDetent != .height(80) {
                            Spacer()
                                .frame(height: 0.5 * max(160 - (viewObject.largeDetentHeight - viewObject.sheetHeight), 0))
                        }
                    }
                }
                .ignoresSafeArea(.keyboard)

            }
            .onChange(of: viewObject.confirmedEqual) { from, to in 
                if to && viewObject.isSearchFocusing {
                    // delaying one runloop (idk if it does anything) technically makes sure sheet is presented
                    DispatchQueue.main.async {
                        isFocused = true
                        viewObject.isSearchFocusing = false
                    }
                }
            
        }
        
        
        
    }
}

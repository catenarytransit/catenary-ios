//
//  mapLibreView.swift
//  catenary-ios
//


import SwiftUI
import MapLibreSwiftUI
import MapLibre
import MapLibreSwiftDSL

struct mapLibreView: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    var styleURL: URL {
            URL(string: colorScheme == .light
                ? "https://maps.catenarymaps.org/light-style.json"
                : "https://maps.catenarymaps.org/dark-style.json")!
        }
    @EnvironmentObject var viewobject: viewObject
    @State var railInFrame = false
    
    let lineColorExpression = NSExpression(
        format: "FUNCTION('#', 'stringByAppendingString:', color)"
    )
    
    let lineTextColorExpression = NSExpression(
        format: "FUNCTION('#', 'stringByAppendingString:', text_color)"
    )
    
    var body: some View {
        MapView(styleURL: styleURL, camera: $viewobject.camera) {
            busLayer()
            otherLayer()
            intercityRailLayer()
            metroRailLayer()
            tramRailLayer()
        }
        .unsafeMapViewControllerModifier { map in
            map.mapView.logoView.isHidden = true
            map.mapView.attributionButton.isHidden = true
        }
        .onMapViewProxyUpdate(onViewProxyChanged: { meae in
            print(meae.zoomLevel)
            
        })
        .ignoresSafeArea()
        
    }
    
    @MapViewContentBuilder
    func busLayer() -> some StyleLayerCollection {
        // BUS SHAPES LAYER
        
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
    
        LineStyleLayer(
                     identifier: LayersPerCategory.Bus.Shapes,
                     source: shapeTileSources.busSource,
                     sourceLayerIdentifier: "data")
        .lineColor(expression: lineColorExpression)
        .lineWidth(interpolatedBy: .zoomLevel,
                     curveType: .linear,
                     parameters: nil,
                     stops: widthStops)
        .lineOpacity(interpolatedBy: .zoomLevel,
                     curveType: .linear,
                     parameters: nil,
                     stops: opacityStops)
        .minimumZoomLevel(railInFrame ? 9 : 8)
        .visible(viewobject.allLayerSettings.bus.shapes)
    
        // BUS SYMBOL LAYER

        SymbolStyleLayer(
                     identifier: LayersPerCategory.Bus.LabelShapes,
                     source: shapeTileSources.busSource,
                     sourceLayerIdentifier: "data")
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
        .textFontSize(interpolatedBy: .zoomLevel,
                     curveType: .linear,
                     parameters: nil,
                     stops: NSExpression(forConstantValue: [11: 7, 13: 9]))
        .minimumZoomLevel(railInFrame ? 13 : 11)
        .visible(viewobject.allLayerSettings.bus.labelshapes)
    }
    
    @MapViewContentBuilder
    func otherLayer() -> some StyleLayerCollection {
        // not( chateau == 'schweiz' AND stop_to_stop_generated == true ) AND (route_type == 6 OR route_type == 7)
        LineStyleLayer(
                     identifier: LayersPerCategory.Other.Shapes,
                     source: shapeTileSources.otherShapesSource,
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
                     source: shapeTileSources.otherShapesSource,
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
                     source: shapeTileSources.otherShapesSource,
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
    }
    
    @MapViewContentBuilder
    func intercityRailLayer() -> some StyleLayerCollection {
        /// ========================
        /// INTERCITY RAIL !! (intercityrailshapes) (i don't know, i'm just copying the kotlin page)
        /// ========================
        
        //shapes
        
        
        LineStyleLayer(
                     identifier: LayersPerCategory.IntercityRail.Shapes,
                     source: shapeTileSources.intercityRailSource,
                     sourceLayerIdentifier: "data")
        .lineColor(expression: lineColorExpression)
        .lineWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [3: 0.4, 5: 0.7, 7: 1.0, 9: 2.0, 11: 2.5]))
        .lineOpacity(expression: NSExpression(forMLNConditional: NSPredicate(format: "stop_to_stop_generated == YES"), trueExpression: NSExpression(forConstantValue: 0.2), falseExpression: NSExpression(forConstantValue: 0.9)))
        .minimumZoomLevel(2)
        .visible(viewobject.allLayerSettings.intercityrail.shapes)
        .predicate(NSPredicate(format: "route_type == 2"))
        
        SymbolStyleLayer(
                     identifier: LayersPerCategory.IntercityRail.LabelShapes,
                     source: shapeTileSources.intercityRailSource,
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
    }
    
    @MapViewContentBuilder
    func metroRailLayer() -> some StyleLayerCollection {
        /// METRO
        
        LineStyleLayer(
                     identifier: LayersPerCategory.Metro.Shapes,
                     source: shapeTileSources.localCityRailSource,
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
                     source: shapeTileSources.localCityRailSource,
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
    }
    
    @MapViewContentBuilder
    func tramRailLayer() -> some StyleLayerCollection {
        ///TRAM: types 0 & 5, it seems
        ///(route_type == 0 OR route_type == 5) AND (NOT (chateau == 'nyct' OR stop_to_stop_generated == TRUE))
        
        LineStyleLayer(
                     identifier: LayersPerCategory.Tram.Shapes,
                     source: shapeTileSources.localCityRailSource,
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
                     source: shapeTileSources.localCityRailSource,
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
    
}

#Preview {
    mapLibreView()
}

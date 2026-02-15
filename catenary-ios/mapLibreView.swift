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
    @ObservedObject var locationManager: LocationManager
    
    var styleURL: URL {
            URL(string: colorScheme == .light
                ? "https://maps.catenarymaps.org/light-style.json"
                : "https://maps.catenarymaps.org/dark-style.json")!
        }
    @EnvironmentObject var viewobject: viewObject
    @State var railInFrame = false
    
    @State private var userFeature: [String: Any]? = nil
    
    let lineColorExpression = NSExpression(
        format: "FUNCTION('#', 'stringByAppendingString:', color)"
    )
    
    let lineTextColorExpression = NSExpression(
        format: "FUNCTION('#', 'stringByAppendingString:', text_color)"
    )
    
    let isMetro = NSPredicate(format: "((ANY route_types == 1 OR ANY children_route_types == 1 OR ANY route_types == 12) AND osm_station_id == nil)")
    let isTram = NSPredicate(format: "(ANY route_types == 0 OR ANY children_route_types == 0 OR ANY route_types == 5) AND NOT (ANY route_types == 1 OR ANY children_route_types == 1 OR ANY route_types == 12 OR osm_station_id == nil) AND osm_station_id == nil")

    
    let baseDisplayName = NSExpression(format: "displayname")
    
    let full: NSExpression = {
    
        let levelSuffix = NSExpression(
            forMLNConditional: NSPredicate(format: "level_id != nil"),
            trueExpression: NSExpression(format: "FUNCTION('; ', 'stringByAppendingString:', level_id)"),
            falseExpression: NSExpression(forConstantValue: "")
        )

        let platformSuffix = NSExpression(
            forMLNConditional: NSPredicate(format: "platform_code != nil"),
            trueExpression: NSExpression(format: "FUNCTION(';', 'stringByAppendingString:', platform_code)"),
            falseExpression: NSExpression(forConstantValue: "")
        )
        
        return NSExpression(
            format: "FUNCTION(FUNCTION(displayname, 'stringByAppendingString:', %@), 'stringByAppendingString:', %@)",
            levelSuffix,
            platformSuffix
        )
    }()
    
    
    var circleInside: UIColor {
          if colorScheme == .dark {
              return UIColor(red: 0x1C/255.0, green: 0x26/255.0, blue: 0x36/255.0, alpha: 1.0)
          } else {
              return UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
          }
      }

      var circleOutside: UIColor {
          if colorScheme == .dark {
              return UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
          } else {
              return UIColor(red: 0x1C/255.0, green: 0x26/255.0, blue: 0x36/255.0, alpha: 1.0)
          }
      }
    
    

    @State var currZoom = 5.0
    @State var coordinateBounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(), ne: CLLocationCoordinate2D())
    
    @MapViewContentBuilder
    var shapeLayer: some StyleLayerCollection {
        //bus
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
                         source: shapeTileSources.busSource(),
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
                         source: shapeTileSources.busSource(),
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
        
        //OTHER
        
        LineStyleLayer(
                     identifier: LayersPerCategory.Other.Shapes,
                     source: shapeTileSources.otherShapesSource(),
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
                     source: shapeTileSources.otherShapesSource(),
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
                     source: shapeTileSources.otherShapesSource(),
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
        
        //INTERCITY RAIL
        
        LineStyleLayer(
                     identifier: LayersPerCategory.IntercityRail.Shapes,
                     source: shapeTileSources.intercityRailSource(),
                     sourceLayerIdentifier: "data")
        .lineColor(expression: lineColorExpression)
        .lineWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [3: 0.4, 5: 0.7, 7: 1.0, 9: 2.0, 11: 2.5]))
        .lineOpacity(expression: NSExpression(forMLNConditional: NSPredicate(format: "stop_to_stop_generated == YES"), trueExpression: NSExpression(forConstantValue: 0.2), falseExpression: NSExpression(forConstantValue: 0.9)))
        .minimumZoomLevel(2)
        .visible(viewobject.allLayerSettings.intercityrail.shapes)
        .predicate(NSPredicate(format: "route_type == 2"))
        
        SymbolStyleLayer(
                     identifier: LayersPerCategory.IntercityRail.LabelShapes,
                     source: shapeTileSources.intercityRailSource(),
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
        
        /// METRO
        
        LineStyleLayer(
                     identifier: LayersPerCategory.Metro.Shapes,
                     source: shapeTileSources.localCityRailSource(),
                     sourceLayerIdentifier: "data")
        .lineColor(expression: lineColorExpression)
        .lineWidth(interpolatedBy: .zoomLevel,
                     curveType: .linear,
                     parameters: nil,
                     stops: NSExpression(forConstantValue: [6: 0.5, 7: 1, 9: 2]))
        .lineOpacity(1)
        .minimumZoomLevel(5)
        .visible(viewobject.allLayerSettings.localrail.shapes)
        .predicate(NSPredicate(format: "(NOT (chateau == 'nyct' AND stop_to_stop_generated == TRUE)) AND (route_type == 1 OR route_type == 12)"))
        
        SymbolStyleLayer(
                     identifier: LayersPerCategory.Metro.LabelShapes,
                     source: shapeTileSources.localCityRailSource(),
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
        .predicate(NSPredicate(format: "(NOT (chateau == 'nyct' AND stop_to_stop_generated == TRUE)) AND (route_type == 1 OR route_type == 12)"))
        
        ///TRAM: types 0 & 5, it seems
        ///(route_type == 0 OR route_type == 5) AND (NOT (chateau == 'nyct' OR stop_to_stop_generated == TRUE))
        
        LineStyleLayer(
                     identifier: LayersPerCategory.Tram.Shapes,
                     source: shapeTileSources.localCityRailSource(),
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
                     source: shapeTileSources.localCityRailSource(),
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
    
    @MapViewContentBuilder
    var stopsLayer: some StyleLayerCollection {
        let busStrokeColorExpression = (colorScheme == .dark ? NSExpression(forMLNStepping: .zoomLevelVariable, from: NSExpression(forConstantValue: UIColor(red: 0xE0/255.0, green: 0xE0/255.0, blue: 0xE0/255.0, alpha: 1.0)), stops: NSExpression(forConstantValue: [14: UIColor(red: 0xDD/255.0, green: 0xDD/255.0, blue: 0xDD/255.0, alpha: 1.0)])): NSExpression(forConstantValue: UIColor(red: 0x33/255.0, green: 0x33/255.0, blue: 0x33/255.0, alpha: 1.0)))
        
        CircleStyleLayer(
            identifier: LayersPerCategory.Bus.Stops,
            source: shapeTileSources.busStopsSource(),
            sourceLayerIdentifier: "data")
        .color(UIColor(red: 28/255, green: 38/255, blue: 54/255, alpha: 1))
        .radius(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                11: 0.8,
                13: 2,
                20: 3
            ])
        )
        .strokeWidth(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                0: 0.8,
                11: 0.8,
                12: 1.2,
            ])
        )
        .strokeColor(expression: busStrokeColorExpression)
        .circleOpacity(0.1)
        .circleStrokeOpacity(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: NSExpression(forConstantValue: 0.5), stops: NSExpression(forConstantValue: [15: 0.6])))
        .minimumZoomLevel(13)
        .visible(viewobject.allLayerSettings.bus.stops)
        
        SymbolStyleLayer(
            identifier: LayersPerCategory.Bus.LabelStops,
            source: shapeTileSources.busStopsSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(format: "displayname"))
        .textFontNames(["Barlow-Medium"])
        .textFontSize(interpolatedBy: .zoomLevel,
                      curveType: .linear,
                      parameters: nil,
                      stops: NSExpression(forConstantValue: [
                          13: 7,
                          15: 8,
                          16: 10
                      ]))
        .textOffset(CGVector(dx: 0.5, dy: 0.5))
        .textColor(colorScheme == .dark ? UIColor(red: 238/255, green: 230/255, blue: 254/255, alpha: 1) : UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1.0))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1) : UIColor(red: 1, green: 1, blue: 1, alpha: 1))
        .textHaloWidth(0.4)
        .minimumZoomLevel(14.7)
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.bus.labelstops)
        
        //othere
        
        
        CircleStyleLayer(
            identifier: LayersPerCategory.Other.Stops,
            source: shapeTileSources.otherStopsSource(),
            sourceLayerIdentifier: "data")
        .color(circleInside)
        .radius(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                8: 1,
                12: 4,
                15: 5
            ])
        )
        .strokeWidth(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: NSExpression(forConstantValue: 1.2), stops: NSExpression(forConstantValue: [13.2: 1.5])))
        .strokeColor(circleOutside)
        .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [10: 0.7, 16: 0.8]))
        .circleStrokeOpacity(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: NSExpression(forConstantValue: 0.5), stops: NSExpression(forConstantValue: [15: 0.6])))
        .minimumZoomLevel(9)
        .visible(viewobject.allLayerSettings.other.stops)
        
        SymbolStyleLayer(
            identifier: LayersPerCategory.Other.LabelStops,
            source: shapeTileSources.otherStopsSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(format: "displayname"))
        .textFontNames(["Barlow-Bold"])
        .textFontSize(interpolatedBy: .zoomLevel,
                      curveType: .linear,
                      parameters: nil,
                      stops: NSExpression(forConstantValue: [
                          9: 6,
                          15: 9,
                          17: 10
                      ]))
        .textOffset(CGVector(dx: 0.5, dy: 1))
        .textColor((colorScheme == .dark) ? UIColor(red: 238/255.0, green: 230/255.0, blue: 254/255.0, alpha: 1) : UIColor(red: 42/255.0, green: 42/255.0, blue: 42/255.0, alpha: 1))
        .textHaloColor((colorScheme == .dark) ? UIColor(red: 15/255.0, green: 23/255.0, blue: 42/255.0, alpha: 1) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(9)
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.other.labelstops)
        
        //intercity
        CircleStyleLayer(
            identifier: LayersPerCategory.IntercityRail.Stops,
            source: shapeTileSources.railStopsSource(),
            sourceLayerIdentifier: "data")
        .color(circleInside)
        .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [7: 1, 8: 2, 9: 3, 12: 5, 15: 8]))
        .strokeColor(circleOutside)
        .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [9: 1, 13.2: 1.5]))
        .circleStrokeOpacity(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: NSExpression(forConstantValue: 0.5), stops: NSExpression(forConstantValue: [13: 0.8])))
        .minimumZoomLevel(7.5)
        .predicate(NSPredicate(format: "ANY route_types == 2 AND osm_station_id == nil"))
        .visible(viewobject.allLayerSettings.intercityrail.labelstops)
        
        
        SymbolStyleLayer(
            identifier: LayersPerCategory.IntercityRail.LabelStops,
            source: shapeTileSources.railStopsSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: baseDisplayName, stops: NSExpression(forConstantValue: [13: full])))
        .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [6: 6, 13: 12]))
        .textOffset(CGVector(dx: 1, dy: 0.2))

        .textFontNames(expression: NSExpression(
            forMLNStepping: .zoomLevelVariable,
            from: NSExpression(forConstantValue: ["Barlow-Regular"]),
            stops: NSExpression(forConstantValue: [
                10: NSExpression(forConstantValue: ["Barlow-Medium"])
            ])
        ))
        .textColor(colorScheme == .dark ? UIColor.white : UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1.0))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(8)
        .predicate(NSPredicate(format: "ANY route_types == 2 AND osm_station_id == nil"))
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.intercityrail.labelstops)
        
        //INTERCITY OSMOSM START
        
        let isOSMInterRail = NSPredicate(format: "(local_ref == nil AND station_type == 'station' AND mode_type == 'rail')") 
        
        CircleStyleLayer(
            identifier: LayersPerCategory.IntercityRail.Stops + "_osm",
            source: shapeTileSources.osmStationsSource(),
            sourceLayerIdentifier: "data")
        .color(circleInside)
        .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [7: 1, 8: 2, 9: 3, 12: 5, 15: 8]))
        .strokeColor(circleOutside)
        .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [9: 1, 13.2: 1.5]))
        .circleStrokeOpacity(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: NSExpression(forConstantValue: 0.5), stops: NSExpression(forConstantValue: [13: 0.8])))
        .minimumZoomLevel(7.5)
        .predicate(isOSMInterRail)
        .visible(viewobject.allLayerSettings.intercityrail.labelstops)
        
        
        SymbolStyleLayer(
            identifier: LayersPerCategory.IntercityRail.LabelStops + "_osm",
            source: shapeTileSources.osmStationsSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(format: "name"))
        .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [6: 6, 13: 12]))
        .textOffset(CGVector(dx: 1, dy: 0.2))

        .textFontNames(expression: NSExpression(
            forMLNStepping: .zoomLevelVariable,
            from: NSExpression(forConstantValue: ["Barlow-Regular"]),
            stops: NSExpression(forConstantValue: [
                10: NSExpression(forConstantValue: ["Barlow-Medium"])
            ])
        ))
        .textColor(colorScheme == .dark ? UIColor.white : UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1.0))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(8)
        .predicate(isOSMInterRail)
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.intercityrail.labelstops)
        
        
        //INTERCITY OSM END
        
        
        
        //local rail
        
        CircleStyleLayer(
            identifier: LayersPerCategory.Metro.Stops,
            source: shapeTileSources.railStopsSource(),
            sourceLayerIdentifier: "data")
        .color(circleInside)
        .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [8: 1, 12: 3, 16: 5]))
        .strokeColor(circleOutside)
        .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [1: 0.8, 10.5: 1, 11: 1.5, 13.2: 2]))
        .circleStrokeOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [1: 0.5, 14.5: 0.5, 15: 0.6]))
        .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [10: 0.7, 16: 0.8]))
        .predicate(isMetro)
        .minimumZoomLevel(9)
        .visible(viewobject.allLayerSettings.localrail.stops)
                
        
        
        
        SymbolStyleLayer(
            identifier: LayersPerCategory.Metro.LabelStops,
            source: shapeTileSources.railStopsSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: baseDisplayName, stops: NSExpression(forConstantValue: [13: full])))
        .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [11: 8, 12: 10, 14: 12, 17: 14]))
        .textOffset(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                
                7: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 1.0),
                    NSExpression(forConstantValue: 0.10)
                ]),
                10: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.9),
                    NSExpression(forConstantValue: 0.30)
                ]),
                12: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.85),
                    NSExpression(forConstantValue: 0.60)
                ])
            ])
        )

        .textFontNames(expression: NSExpression(
            forMLNStepping: .zoomLevelVariable,
            from: NSExpression(forConstantValue: ["Barlow-Regular"]),
            stops: NSExpression(forConstantValue: [
                12: NSExpression(forConstantValue: ["Barlow-Medium"])
            ])
        ))
        .textColor(colorScheme == .dark ? UIColor.white : UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1.0))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(11)
        .predicate(isMetro)
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.localrail.labelstops)
       
        
        //OSM OSM
        let isOSMMetro = NSPredicate(format: "(local_ref == nil AND station_type == 'station' AND mode_type == 'subway')")
        
        CircleStyleLayer(
            identifier: LayersPerCategory.Metro.Stops + "_osm",
            source: shapeTileSources.osmStationsSource(),
            sourceLayerIdentifier: "data")
        .color(circleInside)
        .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [8: 1, 12: 3, 16: 5]))
        .strokeColor(circleOutside)
        .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [1: 0.8, 10.5: 1, 11: 1.5, 13.2: 2]))
        .circleStrokeOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [1: 0.5, 14.5: 0.5, 15: 0.6]))
        .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [10: 0.7, 16: 0.8]))
        .predicate(isOSMMetro)
        .minimumZoomLevel(9)
        .visible(viewobject.allLayerSettings.localrail.stops)
        

        
        
        
        SymbolStyleLayer(
            identifier: LayersPerCategory.Metro.LabelStops + "_osm",
            source: shapeTileSources.osmStationsSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(format: "name"))
        .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [11: 8, 12: 10, 14: 12, 17: 14]))
        .textOffset(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                
                7: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 1.0),
                    NSExpression(forConstantValue: 0.10)
                ]),
                10: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.9),
                    NSExpression(forConstantValue: 0.30)
                ]),
                12: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.85),
                    NSExpression(forConstantValue: 0.60)
                ])
            ])
        )

        .textFontNames(expression: NSExpression(
            forMLNStepping: .zoomLevelVariable,
            from: NSExpression(forConstantValue: ["Barlow-Regular"]),
            stops: NSExpression(forConstantValue: [
                12: NSExpression(forConstantValue: ["Barlow-Medium"])
            ])
        ))
        .textColor(colorScheme == .dark ? UIColor.white : UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1.0))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(10.5)
        .predicate(isOSMMetro)
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.localrail.labelstops)
        
        
        //ENDOSM END OSM
        
        
        
        
        
        
        
        
        
        //tram rail layer
        CircleStyleLayer(
            identifier: LayersPerCategory.Tram.Stops,
            source: shapeTileSources.railStopsSource(),
            sourceLayerIdentifier: "data")
        .color(circleInside)
        .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [9: 1.1, 10: 1.2, 12: 3, 15: 4]))
        .strokeColor(circleOutside)
        .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [1: 1.2, 13.2: 1.2, 13.3: 1.5]))
        .circleStrokeOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [1: 0.4, 11: 0.5, 15: 0.6]))
        .circleOpacity(0.8)
        .minimumZoomLevel(9)
        .predicate(isTram)
        .minimumZoomLevel(9)
        .visible(viewobject.allLayerSettings.localrail.stops)
        
        
        
        SymbolStyleLayer(
            identifier: LayersPerCategory.Tram.LabelStops,
            source: shapeTileSources.railStopsSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: baseDisplayName, stops: NSExpression(forConstantValue: [13: full])))
        .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [9: 7, 11: 7, 12: 9, 14: 10]))
        .textOffset(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                
                7: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 1.0),
                    NSExpression(forConstantValue: 0.20)
                ]),
                10: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.9),
                    NSExpression(forConstantValue: 0.30)
                ]),
                12: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.85),
                    NSExpression(forConstantValue: 0.50)
                ])
            ])
        )

        .textFontNames(expression: NSExpression(
            forMLNStepping: .zoomLevelVariable,
            from: NSExpression(forConstantValue: ["Barlow-Regular"]),
            stops: NSExpression(forConstantValue: [
                12: NSExpression(forConstantValue: ["Barlow-Medium"])
            ])
        ))
        .textColor(colorScheme == .dark ? UIColor.white : UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1.0))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(12)
        .predicate(isTram)
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.localrail.labelstops)
        
        //OSMOSM TRAM START
        let isOSMTram = NSPredicate(format: "(local_ref == nil AND (station_type == 'station' OR station_type == 'tram_stop') AND (mode_type == 'tram' OR mode_type == 'light_rail'))")

        
        CircleStyleLayer(
            identifier: LayersPerCategory.Tram.Stops + "_osm",
            source: shapeTileSources.osmStationsSource(),
            sourceLayerIdentifier: "data")
        .color(circleInside)
        .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [8: 1, 12: 3, 16: 5]))
        .strokeColor(circleOutside)
        .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [1: 0.8, 10.5: 1, 11: 1.5, 13.2: 2]))
        .circleStrokeOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [1: 0.5, 14.5: 0.5, 15: 0.6]))
        .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [10: 0.7, 16: 0.8]))
        .predicate(isOSMTram)
        .minimumZoomLevel(9)
        .visible(viewobject.allLayerSettings.localrail.stops)
        
        
        
        SymbolStyleLayer(
            identifier: LayersPerCategory.Tram.LabelStops + "_osm",
            source: shapeTileSources.osmStationsSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(format: "name"))
        .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [9: 7, 11: 7, 12: 9, 14: 10]))
        .textOffset(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                
                7: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 1.0),
                    NSExpression(forConstantValue: 0.20)
                ]),
                10: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.9),
                    NSExpression(forConstantValue: 0.30)
                ]),
                12: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.85),
                    NSExpression(forConstantValue: 0.50)
                ])
            ])
        )

        .textFontNames(expression: NSExpression(
            forMLNStepping: .zoomLevelVariable,
            from: NSExpression(forConstantValue: ["Barlow-Regular"]),
            stops: NSExpression(forConstantValue: [
                12: NSExpression(forConstantValue: ["Barlow-Medium"])
            ])
        ))
        .textColor(colorScheme == .dark ? UIColor.white : UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1.0))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(11)
        .predicate(isOSMTram)
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.localrail.labelstops)
        
    }
    
    @MapViewContentBuilder
    var stationFeaturesLayer: some StyleLayerCollection {
        SymbolStyleLayer(
            identifier: "stationenter",
            source: shapeTileSources.stationFeaturesSource(),
            sourceLayerIdentifier: "data")
        .iconImage(UIImage.stationEnter)
        .iconScale(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [15: 0.1, 18: 0.2]))
        .iconAllowsOverlap(true)
        //.iconignoreplacement(true)
        .minimumZoomLevel(15)
        
        SymbolStyleLayer(
            identifier: "stationentertxt",
            source: shapeTileSources.stationFeaturesSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(format: "name"))
        .textColor(colorScheme == .dark ? UIColor(red: 186/255, green: 230/255, blue: 253/255, alpha: 1) : UIColor(red: 29.0/255.0, green: 78.0/255.0, blue: 216.0/255.0, alpha: 1.0))
        .textHaloColor(colorScheme == .dark ? UIColor(red: CGFloat(15.0/255.0), green: CGFloat(23.0/255.0), blue: CGFloat(42.0/255.0), alpha: 1.0) : UIColor.white)
        .textHaloWidth(colorScheme == .dark ? 0.4 : 0.2)
        .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [16: 9, 18: 11]))
        .textOffset(CGVector(dx: 1.2, dy: 0))
        .textAnchor("left")
        .textFontNames(["Barlow-Bold"])
        .minimumZoomLevel(17)
        
        SymbolStyleLayer(
            identifier: "platformlabels_osm_intercity",
            source: shapeTileSources.osmStationsSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(
            forConditional: NSPredicate(
                format: "local_ref != nil"
            ),
            trueExpression: NSExpression(forKeyPath: "local_ref"),
            falseExpression: NSExpression(forKeyPath: "ref")
        ))
        .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [14:4, 15:6, 16: 12, 17: 14, 18: 16]))
        .textFontNames(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: NSExpression(forConstantValue: ["Barlow-Regular"]), stops: NSExpression(forConstantValue: [10: NSExpression(forConstantValue: ["Barlow-Medium"]), 13: NSExpression(forConstantValue: ["Barlow-Bold"])])))
        .textAllowsOverlap(true)
        .textColor(UIColor(.white))
        .textHaloColor(UIColor(red: 45/255, green: 50/255, blue: 125/255, alpha: 1))
        .textHaloWidth(1)
        .predicate(NSPredicate(format: "station_type == 'stop_position'"))
        .minimumZoomLevel(14.2)
        
        
        

    }
    
    var body: some View {
        MapView(styleURL: styleURL, camera: $viewobject.camera) {
            shapeLayer
            stationFeaturesLayer
            stopsLayer

            if let loco = locationManager.lastKnownLocation {
                CircleStyleLayer(identifier: "simple-circle", source: ShapeSource(identifier: "dot") { MLNPointFeature(coordinate: loco) })
                    .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [1: 1, 5: 3, 10: 5]))
                
                    .color(.systemBlue)
                    .strokeWidth(2)
                    .strokeColor(.white)
            }
        }
        
        .unsafeMapViewControllerModifier { map in
            map.mapView.logoView.isHidden = true
            map.mapView.attributionButton.isHidden = true
            map.mapView.compassView.isHidden = true
        }
        .onMapViewProxyUpdate(updateMode: .realtime, onViewProxyChanged: { proxy in
                    // 4. Update View State
                    DispatchQueue.main.async {
                        viewobject.currentRotation = proxy.direction
                        
                        var centered = false
                        if let lastLoco = locationManager.lastKnownLocation {
                            if abs(lastLoco.latitude - proxy.centerCoordinate.latitude) < 0.000001 && abs(lastLoco.longitude - proxy.centerCoordinate.longitude) < 0.000001 {
                                centered = true
                            }
                        }
                        viewobject.centered = centered
                        
                        currZoom = proxy.zoomLevel
                        coordinateBounds = proxy.visibleCoordinateBounds
                    }
                    
                })

        .ignoresSafeArea()
        
        
    }
    
}

#Preview {
    mapLibreView(locationManager: LocationManager())
        .environmentObject(viewObject())
}

struct TileBox {
    let north: Int
    let south: Int
    let east: Int
    let west: Int
}

extension MLNCoordinateBounds {
    func toTileBounds(zoom: Double) -> TileBox {
        func latToTileY(_ lat: Double, zoom: Double) -> Int {
            let n = pow(2.0, Double(zoom))
            let latRad = lat * Double.pi / 180.0
            let y = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / Double.pi) / 2.0 * n
            return Int(floor(y))
        }
 
        func lonToTileX(_ lon: Double, zoom: Double) -> Int {
            let n = pow(2.0, zoom)
            return Int(floor((lon + 180.0) / 360.0 * n))
        }
        
        return TileBox(north: latToTileY(self.ne.latitude, zoom: zoom), south: latToTileY(self.sw.latitude, zoom: zoom), east: lonToTileX(self.ne.longitude, zoom: zoom), west: lonToTileX(self.sw.longitude, zoom: zoom))
    }
}



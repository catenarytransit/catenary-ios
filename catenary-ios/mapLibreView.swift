//
//  mapLibreView.swift
//  catenary-ios
//


import SwiftUI
import MapLibreSwiftUI
import MapLibre
import MapLibreSwiftDSL
import UIKit


private enum VehicleFeatureBuilder {
    private struct RGB {
        let r: Int
        let g: Int
        let b: Int
    }

    private struct HSL {
        let h: Double
        let s: Double
        let l: Double
    }

    static func realtime(_ vehicle: RealtimeVehicle, settings: AllLayerSettings) -> MLNPointFeature {
        let feature = MLNPointFeature()
        feature.coordinate = vehicle.coordinate

        let labelSettings = categorySettings(for: Int(vehicle.routeType), settings: settings)
        let color = normalizedHex(vehicle.color, fallback: "AAAAAA")
        let textColor = normalizedHex(vehicle.textColor, fallback: "000000")
        let darkColors = processedColor(color, isDark: true)
        let lightColors = processedColor(color, isDark: false)
        let routeTag = cleanedRouteTag(
            chateauID: vehicle.chateauID,
            routeID: vehicle.routeId,
            shortName: vehicle.routeShortName,
            longName: vehicle.routeLongName
        )
        let tripLabel = cleanedTripLabel(vehicle.tripShortName, tripID: vehicle.tripID)
        let vehicleLabel = cleanedVehicleLabel(vehicle.vehicleLabel ?? vehicle.vehicleID ?? "")
        let headsign = cleanedHeadsign(vehicle.headsign ?? "", chateauID: vehicle.chateauID)
        let speed = vehicle.speedMetresPerSecond.map {
            String(format: "%.1f km/h", $0 * 3.6)
        } ?? ""
        let crowd = occupancySymbol(vehicle.occupancyStatus)
        let delay = delayLabel(vehicle.delay)

        feature.attributes = [
            "selection_kind": "vehicle",
            "chateau": vehicle.chateauID,
            "route_type": Int(vehicle.routeType),
            "bearing": vehicle.bearing ?? 0,
            "has_bearing": vehicle.bearing != nil,
            "vehicle_id": vehicle.vehicleID ?? vehicle.id,
            "vehicle_label": vehicle.vehicleLabel ?? "",
            "vehicleIdLabel": vehicleLabel,
            "gtfs_id": vehicle.chateauID,
            "trip_id": vehicle.tripID ?? "",
            "route_id": vehicle.routeId ?? "",
            "routeId": vehicle.routeId ?? "",
            "headsign": headsign,
            "trip_short_name": vehicle.tripShortName ?? "",
            "tripIdLabel": tripLabel,
            "route_short_name": vehicle.routeShortName ?? "",
            "route_long_name": vehicle.routeLongName ?? "",
            "maptag": routeTag,
            "speed": speed,
            "crowd_symbol": crowd,
            "delay_label": delay,
            "color": color,
            "text_color": textColor,
            "contrastdarkmode": darkColors.label,
            "contrastdarkmodebearing": darkColors.bearing,
            "contrastlightmode": lightColors.label,
            "label_text": labelText(
                settings: labelSettings,
                route: routeTag,
                trip: tripLabel,
                vehicle: vehicleLabel,
                headsign: headsign,
                speed: speed,
                occupancy: crowd,
                delay: delay
            ),
            "start_time": vehicle.startTime ?? "",
            "start_date": vehicle.startDate ?? ""
        ]
        return feature
    }

    static func trajectory(_ vehicle: RealtimeTrajectoryVehicle, settings: AllLayerSettings) -> MLNPointFeature {
        let feature = MLNPointFeature()
        feature.coordinate = vehicle.coordinate

        let labelSettings = categorySettings(for: vehicle.routeType, settings: settings)
        let color = normalizedHex(vehicle.color, fallback: "777777")
        let textColor = normalizedHex(vehicle.textColor, fallback: "FFFFFF")
        let darkColors = processedColor(color, isDark: true)
        let lightColors = processedColor(color, isDark: false)
        let routeTag = cleanedRouteTag(
            chateauID: vehicle.chateauID,
            routeID: vehicle.routeID,
            shortName: vehicle.routeShortName,
            longName: vehicle.routeLongName
        )
        let tripLabel = cleanedTripLabel(vehicle.tripShortName, tripID: vehicle.tripID)
        let vehicleLabel = cleanedVehicleLabel(vehicle.displayName ?? "")
        let headsign = cleanedHeadsign(vehicle.headsign, chateauID: vehicle.chateauID)

        feature.attributes = [
            "selection_kind": "vehicle",
            "route_type": vehicle.routeType,
            "bearing": vehicle.bearing,
            "has_bearing": true,
            "chateau": vehicle.chateauID,
            "gtfs_id": vehicle.chateauID,
            "vehicle_id": vehicle.id,
            "vehicle_label": vehicle.displayName ?? "",
            "vehicleIdLabel": vehicleLabel,
            "trip_id": vehicle.tripID ?? "",
            "route_id": vehicle.routeID ?? "",
            "routeId": vehicle.routeID ?? "",
            "display_name": vehicle.displayName ?? "",
            "headsign": headsign,
            "trip_short_name": vehicle.tripShortName ?? "",
            "tripIdLabel": tripLabel,
            "route_short_name": vehicle.routeShortName ?? "",
            "route_long_name": vehicle.routeLongName ?? "",
            "maptag": routeTag,
            "speed": "",
            "crowd_symbol": "",
            "delay_label": "",
            "color": color,
            "text_color": textColor,
            "contrastdarkmode": darkColors.label,
            "contrastdarkmodebearing": darkColors.bearing,
            "contrastlightmode": lightColors.label,
            "label_text": labelText(
                settings: labelSettings,
                route: routeTag,
                trip: tripLabel,
                vehicle: vehicleLabel,
                headsign: headsign,
                speed: "",
                occupancy: "",
                delay: ""
            ),
            "start_date": vehicle.startDate ?? "",
            "start_time": vehicle.startTime ?? ""
        ]
        return feature
    }

    private static func categorySettings(
        for routeType: Int,
        settings: AllLayerSettings
    ) -> LabelSettings {
        switch routeType {
        case 2, 100, 101, 102, 103, 106, 107:
            return settings.intercityrail.labelrealtimedots
        case 0, 1, 5, 7, 12, 900:
            return settings.localrail.labelrealtimedots
        case 3, 11, 700...799:
            return settings.bus.labelrealtimedots
        default:
            return settings.other.labelrealtimedots
        }
    }

    private static func labelText(
        settings: LabelSettings,
        route: String,
        trip: String,
        vehicle: String,
        headsign: String,
        speed: String,
        occupancy: String,
        delay: String
    ) -> String {
        var firstRow: [String] = []
        if settings.route, !route.isEmpty { firstRow.append(route) }
        if settings.trip, !trip.isEmpty { firstRow.append(trip) }
        if settings.vehicle, !vehicle.isEmpty { firstRow.append(vehicle) }

        var secondRow: [String] = []
        if settings.headsign, !headsign.isEmpty { secondRow.append(headsign) }
        if settings.speed, !speed.isEmpty { secondRow.append(speed) }
        if settings.occupancy, !occupancy.isEmpty { secondRow.append(occupancy) }
        if settings.delay, !delay.isEmpty { secondRow.append(delay) }

        if firstRow.isEmpty { return secondRow.joined(separator: " ") }
        if secondRow.isEmpty { return firstRow.joined(separator: " ") }
        return firstRow.joined(separator: " ") + "\n" + secondRow.joined(separator: " ")
    }

    private static func cleanedVehicleLabel(_ value: String) -> String {
        value
            .replacingOccurrences(of: "ineo-tram:", with: "")
            .replacingOccurrences(of: "ineo-bus:", with: "")
    }

    private static func cleanedTripLabel(_ shortName: String?, tripID: String?) -> String {
        if let shortName, !shortName.isEmpty { return shortName }
        guard let tripID else { return "" }
        let pieces = tripID.split(separator: "_", omittingEmptySubsequences: true)
        guard pieces.count > 1 else { return "" }
        return pieces[1].filter(\.isNumber)
    }

    private static func cleanedHeadsign(_ value: String, chateauID: String) -> String {
        var result = value
        if !result.isEmpty, result == result.uppercased() {
            result = result.lowercased().localizedCapitalized
        }
        if chateauID == "new-south-wales" {
            result = result.replacingOccurrences(of: " Station", with: "")
        }
        if chateauID == "metro~losangeles", result.contains("Line  - ") {
            result = result.split(separator: "-").dropFirst().joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
            .replacingOccurrences(of: "Counterclockwise", with: "ACW")
            .replacingOccurrences(of: "Clockwise", with: "CW")
    }

    private static func cleanedRouteTag(
        chateauID: String,
        routeID: String?,
        shortName: String?,
        longName: String?
    ) -> String {
        var result = [shortName, longName].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.first ?? ""

        let aliases = [
            "Metro E Line": "E",
            "Metro A Line": "A",
            "Metro B Line": "B",
            "Metro C Line": "C",
            "Metro D Line": "D",
            "Metro L Line": "L",
            "Metro K Line": "K",
            "Metrolink Ventura County Line": "Ventura",
            "Metrolink Antelope Valley Line": "Antelope",
            "Metrolink San Bernardino Line": "SB",
            "Metrolink Riverside Line": "Riverside",
            "Metrolink Orange County Line": "Orange",
            "Metrolink 91/Perris Valley Line": "91/Perris",
            "Metrolink Inland Empire-Orange County Line": "IE-OC"
        ]
        result = aliases[result] ?? result
        return result
            .replacingOccurrences(of: " Branch", with: "")
            .replacingOccurrences(of: " Line", with: "")
            .replacingOccurrences(of: "Counterclockwise", with: "ACW")
            .replacingOccurrences(of: "Clockwise", with: "CW")
    }

    private static func occupancySymbol(_ status: Int32?) -> String {
        switch status {
        case 0: return "\u{2205}"
        case 1: return "\u{25A2}"
        case 2: return "\u{25A3}"
        case 3: return "\u{256C}"
        case 4: return "\u{256C}\u{2639}\u{256C}"
        case 5: return "\u{25A0}"
        case 6, 8: return "\u{2717}"
        default: return ""
        }
    }

    private static func delayLabel(_ delay: Int32?) -> String {
        guard let delay else { return "" }
        let prefix = delay < 0 ? "-" : "+"
        let totalMinutes = abs(Int(delay)) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return prefix + (hours > 0 ? "\(hours)h" : "") + "\(minutes)m"
    }

    private static func normalizedHex(_ input: String?, fallback: String) -> String {
        let value = (input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard value.count == 6, value.allSatisfy(\.isHexDigit) else {
            return fallback.uppercased()
        }
        return value.uppercased()
    }

    private static func processedColor(_ input: String, isDark: Bool) -> (label: String, bearing: String) {
        guard let rgb = rgb(from: input) else { return (input, input) }
        if isDark {
            let hsl = rgbToHsl(rgb)
            var newLightness = hsl.l
            if hsl.l < 60 {
                let blueOffset = rgb.b > 40 ? 30 * (Double(rgb.b) / 255.0) : 0
                newLightness = hsl.l + 10 + 25 * ((100 - hsl.s) / 100) + blueOffset
                if newLightness > 60 { newLightness = 60 + blueOffset }
                newLightness = min(sqrt(hsl.l * 25) + 40, 100)
            }
            let label = hslToRgb(HSL(h: hsl.h, s: hsl.s, l: newLightness))
            let bearing = hslToRgb(HSL(h: hsl.h, s: hsl.s, l: (newLightness + hsl.l) / 2))
            return (hex(label), hex(bearing))
        }

        let gamma = (0.299 * Double(rgb.r) + 0.587 * Double(rgb.g) + 0.114 * Double(rgb.b)) / 255
        guard gamma > 0.55 else { return (hex(rgb), hex(rgb)) }
        let factor = 0.55 / gamma
        let adjusted = RGB(
            r: min(255, max(0, Int((Double(rgb.r) * factor).rounded()))),
            g: min(255, max(0, Int((Double(rgb.g) * factor).rounded()))),
            b: min(255, max(0, Int((Double(rgb.b) * factor).rounded())))
        )
        return (hex(adjusted), hex(adjusted))
    }

    private static func rgb(from hex: String) -> RGB? {
        let value = normalizedHex(hex, fallback: "")
        guard value.count == 6,
              let r = Int(value.prefix(2), radix: 16),
              let g = Int(value.dropFirst(2).prefix(2), radix: 16),
              let b = Int(value.suffix(2), radix: 16) else { return nil }
        return RGB(r: r, g: g, b: b)
    }

    private static func hex(_ rgb: RGB) -> String {
        String(format: "%02X%02X%02X", rgb.r, rgb.g, rgb.b)
    }

    private static func rgbToHsl(_ rgb: RGB) -> HSL {
        let r = Double(rgb.r) / 255
        let g = Double(rgb.g) / 255
        let b = Double(rgb.b) / 255
        let maximum = max(r, max(g, b))
        let minimum = min(r, min(g, b))
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        var hue = 0.0
        if delta != 0 {
            if maximum == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximum == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue *= 60
            if hue < 0 { hue += 360 }
        }
        return HSL(h: hue, s: saturation * 100, l: lightness * 100)
    }

    private static func hslToRgb(_ hsl: HSL) -> RGB {
        let hue = ((hsl.h.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let saturation = min(100, max(0, hsl.s)) / 100
        let lightness = min(100, max(0, hsl.l)) / 100
        if saturation == 0 {
            let value = Int((lightness * 255).rounded())
            return RGB(r: value, g: value, b: value)
        }
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let x = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - chroma / 2
        let channels: (Double, Double, Double)
        switch hue {
        case ..<60: channels = (chroma, x, 0)
        case ..<120: channels = (x, chroma, 0)
        case ..<180: channels = (0, chroma, x)
        case ..<240: channels = (0, x, chroma)
        case ..<300: channels = (x, 0, chroma)
        default: channels = (chroma, 0, x)
        }
        return RGB(
            r: Int(((channels.0 + m) * 255).rounded()),
            g: Int(((channels.1 + m) * 255).rounded()),
            b: Int(((channels.2 + m) * 255).rounded())
        )
    }
}


final class MapFeatureTapCoordinator: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    private weak var mapView: MLNMapView?
    private weak var navigator: viewObject?
    private var recognizer: UITapGestureRecognizer?
    private var layerSettings = AllLayerSettings()
    private var realtimeVehicles: [RealtimeVehicle] = []
    private var trajectoryVehicles: [RealtimeTrajectoryVehicle] = []
    private var realtimeFeatureCache: [String: MLNPointFeature] = [:]
    private var trajectoryFeatureCache: [String: MLNPointFeature] = [:]

    private let selectableLayerIDs: Set<String> = [
        LayersPerCategory.IntercityRail.Livedots,
        LayersPerCategory.Metro.Livedots,
        LayersPerCategory.Tram.Livedots,
        LayersPerCategory.Bus.Livedots,
        LayersPerCategory.Other.Livedots,
        LayersPerCategory.Other.Livedots + "_aerial",
        LayersPerCategory.TrajectoryIntercityRail.Livedots,
        LayersPerCategory.TrajectoryMetro.Livedots,
        LayersPerCategory.TrajectoryTram.Livedots,
        LayersPerCategory.TrajectoryBus.Livedots,
        LayersPerCategory.TrajectoryOther.Livedots,
        LayersPerCategory.TrajectoryOther.Livedots + "_aerial",
        LayersPerCategory.Bus.Shapes,
        LayersPerCategory.Bus.LabelShapes,
        LayersPerCategory.Bus.Stops,
        LayersPerCategory.Bus.LabelStops,
        LayersPerCategory.IntercityRail.Shapes,
        LayersPerCategory.IntercityRail.LabelShapes,
        LayersPerCategory.IntercityRail.Stops,
        LayersPerCategory.IntercityRail.LabelStops,
        LayersPerCategory.Metro.Shapes,
        LayersPerCategory.Metro.LabelShapes,
        LayersPerCategory.Metro.Stops,
        LayersPerCategory.Metro.LabelStops,
        LayersPerCategory.Tram.Shapes,
        LayersPerCategory.Tram.LabelShapes,
        LayersPerCategory.Tram.Stops,
        LayersPerCategory.Tram.LabelStops,
        LayersPerCategory.Other.Shapes,
        LayersPerCategory.Other.LabelShapes,
        LayersPerCategory.Other.Stops,
        LayersPerCategory.Other.LabelStops,
        LayersPerCategory.Bus.Stops + "_osm",
        LayersPerCategory.Bus.LabelStops + "_osm",
        LayersPerCategory.IntercityRail.Stops + "_osm",
        LayersPerCategory.IntercityRail.LabelStops + "_osm",
        "intercityrail-ranked-1",
        "intercityrail-ranked-label-1",
        "intercityrail-ranked-2",
        "intercityrail-ranked-label-2",
        "intercityrail-ranked-3",
        "intercityrail-ranked-label-3",
        "intercityrail-ranked-4",
        "intercityrail-ranked-label-4",
        "intercityrail-ranked-5",
        "intercityrail-ranked-label-5",
        "intercityrail-ranked-6",
        "intercityrail-ranked-label-6",
        LayersPerCategory.Metro.Stops + "_osm",
        LayersPerCategory.Metro.LabelStops + "_osm",
        LayersPerCategory.Tram.Stops + "_osm",
        LayersPerCategory.Tram.LabelStops + "_osm",
        LayersPerCategory.Other.Stops + "_osm",
        LayersPerCategory.Other.LabelStops + "_osm"
    ]

    func install(on mapView: MLNMapView, navigator: viewObject) {
        self.navigator = navigator
        guard self.mapView !== mapView else { return }

        if let recognizer, let oldMap = self.mapView {
            oldMap.removeGestureRecognizer(recognizer)
        }

        self.mapView = mapView
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        mapView.addGestureRecognizer(recognizer)
        self.recognizer = recognizer
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let mapView, let navigator else { return }
        let point = recognizer.location(in: mapView)
        let hitArea = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
        let features = mapView.visibleFeatures(
            in: hitArea,
            inStyleLayersWithIdentifiers: selectableLayerIDs,
            predicate: nil
        )

        var seen = Set<String>()
        let options = features.compactMap { makeOption(from: $0) }.filter { seen.insert($0.id).inserted }
        guard !options.isEmpty else { return }

        let destination: CatenaryStackItem
        if let option = options.first, options.count == 1 {
            destination = option.destination
        } else {
            destination = .mapSelectionScreen(options: options)
        }

        if let current = navigator.currentStackItem, case .mapSelectionScreen = current {
            navigator.replaceTop(with: destination)
        } else {
            navigator.push(destination)
        }
    }

    private func makeOption(from feature: MLNFeature) -> MapSelectionOption? {
        let latitude = (feature as? MLNPointFeature)?.coordinate.latitude
        let longitude = (feature as? MLNPointFeature)?.coordinate.longitude

        if string(feature, keys: ["selection_kind"]) == "vehicle",
           let chateauID = string(feature, keys: ["chateau", "chateau_id"]),
           let routeType = integer(feature, keys: ["route_type"]) {
            return MapSelectionOption(data: .vehicle(
                chateauID: chateauID,
                vehicleID: string(feature, keys: ["vehicle_id"]),
                routeID: string(feature, keys: ["route_id"]),
                headsign: string(feature, keys: ["headsign", "trip_headsign"]) ?? "",
                tripLabel: string(feature, keys: ["vehicle_label", "display_name"]),
                colour: string(feature, keys: ["color", "colour"]) ?? "777777",
                routeShortName: string(feature, keys: ["route_short_name", "route_label"]),
                routeLongName: string(feature, keys: ["route_long_name"]),
                routeType: routeType,
                tripShortName: string(feature, keys: ["trip_short_name"]),
                textColour: string(feature, keys: ["text_color", "text_colour"]) ?? "FFFFFF",
                gtfsID: string(feature, keys: ["gtfs_id"]) ?? chateauID,
                tripID: string(feature, keys: ["trip_id", "unique_trip_id"]),
                startTime: string(feature, keys: ["start_time"]),
                startDate: string(feature, keys: ["start_date"])
            ))
        }

        if let osmID = string(feature, keys: ["osm_station_id", "osm_id"]),
           let latitude,
           let longitude {
            return MapSelectionOption(data: .osmStation(
                osmID: osmID,
                name: string(feature, keys: ["name", "displayname"]) ?? "Station",
                modeType: string(feature, keys: ["mode_type", "station_type"]) ?? "station",
                latitude: latitude,
                longitude: longitude
            ))
        }

        if let chateauID = string(feature, keys: ["chateau", "chateau_id"]),
           let stopID = string(feature, keys: ["stop_id", "gtfs_id"]) {
            return MapSelectionOption(data: .stop(
                chateauID: chateauID,
                stopID: stopID,
                stopName: string(feature, keys: ["displayname", "stop_name", "name"]) ?? stopID
            ))
        }

        if let chateauID = string(feature, keys: ["chateau", "chateau_id"]),
           let routeID = string(feature, keys: ["route_id"]) {
            return MapSelectionOption(data: .route(
                chateauID: chateauID,
                routeID: routeID,
                colour: string(feature, keys: ["color", "colour"]) ?? "000000",
                name: string(feature, keys: ["route_label", "short_name", "long_name"]),
                routeType: integer(feature, keys: ["route_type"])
            ))
        }

        return nil
    }

    private func string(_ feature: MLNFeature, keys: [String]) -> String? {
        for key in keys {
            guard let value = feature.attributes[key], !(value is NSNull) else { continue }
            if let value = value as? String, !value.isEmpty { return value }
            if let value = value as? NSNumber { return value.stringValue }
        }
        return nil
    }

    func updateLayerSettings(_ settings: AllLayerSettings) {
        layerSettings = settings
        realtimeFeatureCache.removeAll(keepingCapacity: true)
        trajectoryFeatureCache.removeAll(keepingCapacity: true)
        rebuildRealtimeSource()
        rebuildTrajectorySource()
    }

    func updateRealtimeVehicles(_ vehicles: [RealtimeVehicle]) {
        let previousByID = Dictionary(
            realtimeVehicles.map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        realtimeVehicles = vehicles
        let liveIDs = Set(vehicles.map(\.id))
        realtimeFeatureCache = realtimeFeatureCache.filter { liveIDs.contains($0.key) }

        for vehicle in vehicles
        where previousByID[vehicle.id] != vehicle || realtimeFeatureCache[vehicle.id] == nil {
            realtimeFeatureCache[vehicle.id] = VehicleFeatureBuilder.realtime(
                vehicle,
                settings: layerSettings
            )
        }
        publishRealtimeSource()
    }

    func updateTrajectoryVehicles(_ vehicles: [RealtimeTrajectoryVehicle]) {
        let previousByID = Dictionary(
            trajectoryVehicles.map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        trajectoryVehicles = vehicles
        let liveIDs = Set(vehicles.map(\.id))
        trajectoryFeatureCache = trajectoryFeatureCache.filter { liveIDs.contains($0.key) }

        for vehicle in vehicles {
            if let feature = trajectoryFeatureCache[vehicle.id],
               let previous = previousByID[vehicle.id],
               sameTrajectoryMetadata(previous, vehicle) {
                feature.coordinate = vehicle.coordinate
                var attributes = feature.attributes
                attributes["bearing"] = vehicle.bearing
                feature.attributes = attributes
            } else {
                trajectoryFeatureCache[vehicle.id] = VehicleFeatureBuilder.trajectory(
                    vehicle,
                    settings: layerSettings
                )
            }
        }
        publishTrajectorySource()
    }

    func updateWildfireFeatures(_ features: [MLNPointFeature]) {
        guard let source = mapView?.style?.source(
            withIdentifier: WildfireMapIdentifiers.fireNamesSource
        ) as? MLNShapeSource else { return }

        let shapes: [MLNShape & MLNFeature] = features.map { $0 }
        source.shape = MLNShapeCollectionFeature(shapes: shapes)
    }

    private func rebuildRealtimeSource() {
        realtimeFeatureCache.removeAll(keepingCapacity: true)
        for vehicle in realtimeVehicles {
            realtimeFeatureCache[vehicle.id] = VehicleFeatureBuilder.realtime(
                vehicle,
                settings: layerSettings
            )
        }
        publishRealtimeSource()
    }

    private func publishRealtimeSource() {
        guard let source = mapView?.style?.source(
            withIdentifier: "realtime-vehicles"
        ) as? MLNShapeSource else { return }
        let features: [MLNShape & MLNFeature] = realtimeVehicles.compactMap {
            realtimeFeatureCache[$0.id]
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func rebuildTrajectorySource() {
        trajectoryFeatureCache.removeAll(keepingCapacity: true)
        for vehicle in trajectoryVehicles {
            trajectoryFeatureCache[vehicle.id] = VehicleFeatureBuilder.trajectory(
                vehicle,
                settings: layerSettings
            )
        }
        publishTrajectorySource()
    }

    private func publishTrajectorySource() {
        guard let source = mapView?.style?.source(
            withIdentifier: "trajectory-vehicles"
        ) as? MLNShapeSource else { return }
        let features: [MLNShape & MLNFeature] = trajectoryVehicles.compactMap {
            trajectoryFeatureCache[$0.id]
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func sameTrajectoryMetadata(
        _ lhs: RealtimeTrajectoryVehicle,
        _ rhs: RealtimeTrajectoryVehicle
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.routeType == rhs.routeType
            && lhs.chateauID == rhs.chateauID
            && lhs.tripID == rhs.tripID
            && lhs.routeID == rhs.routeID
            && lhs.displayName == rhs.displayName
            && lhs.headsign == rhs.headsign
            && lhs.tripShortName == rhs.tripShortName
            && lhs.routeShortName == rhs.routeShortName
            && lhs.routeLongName == rhs.routeLongName
            && lhs.color == rhs.color
            && lhs.textColor == rhs.textColor
            && lhs.startDate == rhs.startDate
            && lhs.startTime == rhs.startTime
    }
    func updateSelectedStop(_ context: SelectedStopMapContext?) {
        guard let source = mapView?.style?.source(
            withIdentifier: "selected-stop-context"
        ) as? MLNShapeSource else { return }

        let features: [MLNShape & MLNFeature]
        if let context {
            let feature = MLNPointFeature()
            feature.coordinate = context.coordinate
            feature.attributes = ["name": context.name]
            features = [feature]
        } else {
            features = []
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func integer(_ feature: MLNFeature, keys: [String]) -> Int? {
        for key in keys {
            guard let value = feature.attributes[key], !(value is NSNull) else { continue }
            if let value = value as? NSNumber { return value.intValue }
            if let value = value as? String, let parsed = Int(value) { return parsed }
        }
        return nil
    }
}

struct mapLibreView: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var nearbyPinMapCoordinator: NearbyPinMapCoordinator
    let nearbyPinActive: Bool
    let nearbyPinCoordinate: CLLocationCoordinate2D?
    let contentInset: UIEdgeInsets
    @StateObject private var realtimeVM = RealtimeVehicles()
    @StateObject private var trajectoryVM = RealtimeTrajectories()
    @StateObject private var wildfireVM = WildfireMapData()
    @StateObject private var featureTapCoordinator = MapFeatureTapCoordinator()
    
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
            .textFontNames(["Arimo-Regular"])
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
        .textFontNames(["Arimo-Regular"])
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
        .textFontNames(["Arimo-Bold"])
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
        .textFontNames(["Arimo-Bold"])
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
        .textFontNames(["Arimo-Medium"])
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
        .textFontNames(["Arimo-Medium"])
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
        .textFontNames(["Arimo-Bold"])
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
        .visible(viewobject.allLayerSettings.intercityrail.stops)
        
        
        SymbolStyleLayer(
            identifier: LayersPerCategory.IntercityRail.LabelStops,
            source: shapeTileSources.railStopsSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: baseDisplayName, stops: NSExpression(forConstantValue: [13: full])))
        .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [6: 6, 13: 12]))
        .textOffset(CGVector(dx: 1, dy: 0.2))

        .textFontNames(expression: NSExpression(
            forMLNStepping: .zoomLevelVariable,
            from: NSExpression(forConstantValue: ["Arimo-Regular"]),
            stops: NSExpression(forConstantValue: [
                10: NSExpression(forConstantValue: ["Arimo-Medium"])
            ])
        ))
        .textColor(colorScheme == .dark ? UIColor.white : UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1.0))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(8)
        .predicate(NSPredicate(format: "ANY route_types == 2 AND osm_station_id == nil"))
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.intercityrail.labelstops)
        
        rankedIntercityStationLayers(rank: 6, minimumCircleZoom: 8, minimumLabelZoom: 10)
        rankedIntercityStationLayers(rank: 5, minimumCircleZoom: 7.5, minimumLabelZoom: 9.5)
        rankedIntercityStationLayers(rank: 4, minimumCircleZoom: 6.5, minimumLabelZoom: 8.5)
        rankedIntercityStationLayers(rank: 3, minimumCircleZoom: 5, minimumLabelZoom: 7)
        rankedIntercityStationLayers(rank: 2, minimumCircleZoom: 5, minimumLabelZoom: 6.5)
        rankedIntercityStationLayers(rank: 1, minimumCircleZoom: 4, minimumLabelZoom: 4)
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
            from: NSExpression(forConstantValue: ["Arimo-Regular"]),
            stops: NSExpression(forConstantValue: [
                12: NSExpression(forConstantValue: ["Arimo-Medium"])
            ])
        ))
        .textColor(colorScheme == .dark ? UIColor.white : UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1.0))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(11)
        .predicate(isMetro)
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.localrail.labelstops)
       
        
        // Ranked OSM subway stations.
        let isOSMMetro = NSPredicate(format: "local_ref == nil AND station_type == 'station' AND mode_type == 'subway' AND number_of_associated_stops != 0")
        let isOSMMetroLabel = NSPredicate(format: "station_type == 'station' AND mode_type == 'subway' AND number_of_associated_stops != 0")

        CircleStyleLayer(
            identifier: LayersPerCategory.Metro.Stops + "_osm",
            source: shapeTileSources.osmStationsRankedSource(),
            sourceLayerIdentifier: "data")
        .color(ranked3456Inside)
        .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [5: 0.8, 8: 1.2, 12: 2.8, 15: 4.8]))
        .strokeColor(ranked3456Outside)
        .strokeWidth(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: NSExpression(forConstantValue: 1), stops: NSExpression(forConstantValue: [11: 1.8, 12: 3.0])))
        .circleStrokeOpacity(1)
        .circleOpacity(1)
        .predicate(isOSMMetro)
        .minimumZoomLevel(10.5)
        .visible(viewobject.allLayerSettings.localrail.stops)

        SymbolStyleLayer(
            identifier: LayersPerCategory.Metro.LabelStops + "_osm",
            source: shapeTileSources.osmStationsRankedSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(format: "name"))
        .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [11: 8, 12: 10, 14: 12, 16: 14]))
        .textOffset(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                7: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.0),
                    NSExpression(forConstantValue: 0.10)
                ]),
                10: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.0),
                    NSExpression(forConstantValue: 0.30)
                ]),
                12: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.0),
                    NSExpression(forConstantValue: 0.60)
                ])
            ])
        )
        .textFontNames(expression: NSExpression(
            forMLNStepping: .zoomLevelVariable,
            from: NSExpression(forConstantValue: ["Arimo-Regular"]),
            stops: NSExpression(forConstantValue: [
                12: NSExpression(forConstantValue: ["Arimo-Medium"]),
                15: NSExpression(forConstantValue: ["Arimo-SemiBold"])
            ])
        ))
        .textColor(expression: osmStationLabelTextColor(startZoom: 13))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(13)
        .predicate(isOSMMetroLabel)
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.localrail.labelstops)
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
            from: NSExpression(forConstantValue: ["Arimo-Regular"]),
            stops: NSExpression(forConstantValue: [
                12: NSExpression(forConstantValue: ["Arimo-Medium"])
            ])
        ))
        .textColor(colorScheme == .dark ? UIColor.white : UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1.0))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(12)
        .predicate(isTram)
        .textAnchor("left")
        .visible(viewobject.allLayerSettings.localrail.labelstops)
        
        // Ranked OSM tram/light-rail stations.
        let isOSMTram = NSPredicate(format: "local_ref == nil AND parent_osm_id == nil AND (station_type == 'station' OR station_type == 'tram_stop' OR station_type == 'halt') AND number_of_associated_stops != 0 AND (mode_type == 'tram' OR mode_type == 'light_rail')")

        CircleStyleLayer(
            identifier: LayersPerCategory.Tram.Stops + "_osm",
            source: shapeTileSources.osmStationsRankedSource(),
            sourceLayerIdentifier: "data")
        .color(ranked3456Inside)
        .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [5: 0.6, 8: 1, 12: 2, 15: 4]))
        .strokeColor(ranked3456Outside)
        .strokeWidth(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: NSExpression(forConstantValue: 1.8), stops: NSExpression(forConstantValue: [12: 3.0])))
        .circleStrokeOpacity(1)
        .circleOpacity(1)
        .predicate(isOSMTram)
        .minimumZoomLevel(12)
        .visible(viewobject.allLayerSettings.localrail.stops)

        SymbolStyleLayer(
            identifier: LayersPerCategory.Tram.LabelStops + "_osm",
            source: shapeTileSources.osmStationsRankedSource(),
            sourceLayerIdentifier: "data")
        .text(expression: NSExpression(format: "name"))
        .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil, stops: NSExpression(forConstantValue: [9: 7, 11: 7, 12: 9, 14: 10, 16: 12, 18: 14]))
        .textOffset(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                7: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.0),
                    NSExpression(forConstantValue: 0.20)
                ]),
                10: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.0),
                    NSExpression(forConstantValue: 0.30)
                ]),
                12: NSExpression(forAggregate: [
                    NSExpression(forConstantValue: 0.0),
                    NSExpression(forConstantValue: 0.50)
                ])
            ])
        )
        .textFontNames(expression: NSExpression(
            forMLNStepping: .zoomLevelVariable,
            from: NSExpression(forConstantValue: ["Arimo-Regular"]),
            stops: NSExpression(forConstantValue: [
                13: NSExpression(forConstantValue: ["Arimo-Medium"]),
                16: NSExpression(forConstantValue: ["Arimo-SemiBold"])
            ])
        ))
        .textColor(expression: osmStationLabelTextColor(startZoom: 14))
        .textHaloColor(colorScheme == .dark ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) : UIColor.white)
        .textHaloWidth(1)
        .minimumZoomLevel(14)
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
        .textFontNames(["Arimo-Bold"])
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
        .textFontNames(expression: NSExpression(forMLNStepping: .zoomLevelVariable, from: NSExpression(forConstantValue: ["Arimo-Regular"]), stops: NSExpression(forConstantValue: [10: NSExpression(forConstantValue: ["Arimo-Medium"]), 13: NSExpression(forConstantValue: ["Arimo-Bold"])])))
        .textAllowsOverlap(true)
        .textColor(UIColor(.white))
        .textHaloColor(UIColor(red: 45/255, green: 50/255, blue: 125/255, alpha: 1))
        .textHaloWidth(1)
        .predicate(NSPredicate(format: "station_type == 'stop_position'"))
        .minimumZoomLevel(14.2)
    }

    /// Live vehicle position dots, enriched with route metadata from Birch.
    @MapViewContentBuilder
    var realtimeLayer: some StyleLayerCollection {
        let source = ShapeSource(identifier: "realtime-vehicles") {
            for vehicle in realtimeVM.vehicles {
                VehicleFeatureBuilder.realtime(vehicle, settings: viewobject.allLayerSettings)
            }
        }
        let dotStroke = colorScheme == .dark
            ? UIColor(red: 46/255, green: 57/255, blue: 75/255, alpha: 1)
            : UIColor.white
        let labelHalo = colorScheme == .dark
            ? UIColor(red: 30/255, green: 41/255, blue: 59/255, alpha: 1)
            : UIColor(red: 237/255, green: 237/255, blue: 237/255, alpha: 1)
        let labelColor = NSExpression(
            format: "FUNCTION('#', 'stringByAppendingString:', \(colorScheme == .dark ? "contrastdarkmode" : "contrastlightmode"))"
        )
        let otherPredicate = NSPredicate(
            format: "route_type != 0 AND route_type != 1 AND route_type != 2 AND route_type != 3 AND route_type != 5 AND route_type != 6 AND route_type != 11 AND route_type != 12"
        )

        CircleStyleLayer(identifier: LayersPerCategory.IntercityRail.Livedots, source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [1: 0.8, 3: 2.0, 6: 2.3, 8: 3.5, 11: 5.5, 16: 9.5]))
            .strokeColor(dotStroke)
            .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                         stops: NSExpression(forConstantValue: [3: 0.6, 5: 0.7, 7: 0.8]))
            .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                           stops: NSExpression(forConstantValue: [4: 0.8, 7: 0.9, 11: 1.0]))
            .circleStrokeOpacity(1)
            .predicate(NSPredicate(format: "route_type == 2"))
            .minimumZoomLevel(1)
            .visible(viewobject.allLayerSettings.intercityrail.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.IntercityRail.Labeldots, source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-Medium"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: [6: 8, 9: 8, 11: 9.6, 13: 11.2, 16: 14.4]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2.4 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(NSPredicate(format: "route_type == 2"))
            .minimumZoomLevel(2.5)
            .visible(viewobject.allLayerSettings.intercityrail.visiblerealtimedots)

        CircleStyleLayer(identifier: LayersPerCategory.Metro.Livedots, source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [6: 2.5, 8: 2.3, 10: 3.0, 11: 4.5, 14: 6.5, 16: 10.5]))
            .strokeColor(dotStroke)
            .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                         stops: NSExpression(forConstantValue: [8: 0.8, 10: 1.2]))
            .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                           stops: NSExpression(forConstantValue: [7: 0.8, 9: 1.0]))
            .circleStrokeOpacity(1)
            .predicate(NSPredicate(format: "route_type == 1 OR route_type == 12"))
            .minimumZoomLevel(6)
            .visible(viewobject.allLayerSettings.localrail.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.Metro.Labeldots, source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-Medium"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: [6: 5, 9: 6.4, 10: 7.2, 11: 8, 13: 9.6, 15: 12.8]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2.4 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(NSPredicate(format: "route_type == 1 OR route_type == 12"))
            .minimumZoomLevel(8)
            .visible(viewobject.allLayerSettings.localrail.visiblerealtimedots)

        CircleStyleLayer(identifier: LayersPerCategory.Tram.Livedots, source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [6: 1.5, 8: 2.0, 10: 3.5, 11: 4.0, 13: 5.5, 15: 4.5, 16: 9.5]))
            .strokeColor(dotStroke)
            .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                         stops: NSExpression(forConstantValue: [8: 0.5, 9: 0.6, 10: 1.0]))
            .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                           stops: NSExpression(forConstantValue: [7: 0.8, 9: 1.0]))
            .circleStrokeOpacity(1)
            .predicate(NSPredicate(format: "route_type == 0 OR route_type == 5"))
            .minimumZoomLevel(6.5)
            .visible(viewobject.allLayerSettings.localrail.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.Tram.Labeldots, source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-Medium"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: [6: 4, 9: 6, 10: 7, 11: 6.4, 13: 8, 15: 11.2]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2.4 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(NSPredicate(format: "route_type == 0 OR route_type == 5"))
            .minimumZoomLevel(8)
            .visible(viewobject.allLayerSettings.localrail.visiblerealtimedots)

        CircleStyleLayer(identifier: LayersPerCategory.Bus.Livedots, source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [7: 1.2, 8: 1.6, 9: 1.7, 10: 2.0, 16: 6.0]))
            .strokeColor(dotStroke)
            .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                         stops: NSExpression(forConstantValue: [9: railInFrame ? 0.4 : 0.8, 14: 1.0]))
            .circleOpacity(railInFrame ? 0.5 : 0.8)
            .circleStrokeOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                                 stops: NSExpression(forConstantValue: [7.9: 0.0, 8: 0.3, 9: 0.5, 13: 0.9]))
            .predicate(NSPredicate(format: "route_type == 3 OR route_type == 11"))
            .minimumZoomLevel(9)
            .visible(viewobject.allLayerSettings.bus.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.Bus.Labeldots, source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-SemiBold"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: viewobject.allLayerSettings.bus.labelrealtimedots.headsign
                              ? [9: 4, 11: 5, 12: 7, 13: 9, 15: 11]
                              : [9: 5, 11: 7, 13: 10, 15: 13]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(NSPredicate(format: "route_type == 3 OR route_type == 11"))
            .minimumZoomLevel(13)
            .visible(viewobject.allLayerSettings.bus.visiblerealtimedots)

        CircleStyleLayer(identifier: LayersPerCategory.Other.Livedots, source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [8: 5.0, 10: 6.0, 16: 8.0]))
            .strokeColor(dotStroke)
            .strokeWidth(1)
            .circleOpacity(0.5)
            .circleStrokeOpacity(1)
            .predicate(otherPredicate)
            .minimumZoomLevel(3)
            .visible(viewobject.allLayerSettings.other.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.Other.Labeldots, source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-Medium"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: [9: 8.5, 11: 13, 13: 16]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2.4 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(otherPredicate)
            .minimumZoomLevel(3)
            .visible(viewobject.allLayerSettings.other.visiblerealtimedots)

        CircleStyleLayer(identifier: LayersPerCategory.Other.Livedots + "_aerial", source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [6: 1.5, 8: 2.0, 10: 3.5, 11: 4.0, 13: 5.5, 15: 4.5, 16: 9.5]))
            .strokeColor(dotStroke)
            .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                         stops: NSExpression(forConstantValue: [8: 0.5, 9: 0.6, 10: 1.0]))
            .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                           stops: NSExpression(forConstantValue: [7: 0.8, 9: 1.0]))
            .circleStrokeOpacity(1)
            .predicate(NSPredicate(format: "route_type == 6"))
            .minimumZoomLevel(6.5)
            .visible(viewobject.allLayerSettings.other.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.Other.Labeldots + "_aerial", source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-Medium"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: [6: 4, 9: 6, 10: 7, 11: 6.4, 13: 8, 15: 11.2]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2.4 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(NSPredicate(format: "route_type == 6"))
            .minimumZoomLevel(8)
            .visible(viewobject.allLayerSettings.other.visiblerealtimedots)
    }

    /// Synthetic positions interpolated from Spruce trajectory buffers.
    @MapViewContentBuilder
    var trajectoryLayer: some StyleLayerCollection {
        let source = ShapeSource(identifier: "trajectory-vehicles") {
            for vehicle in trajectoryVM.vehicles {
                VehicleFeatureBuilder.trajectory(vehicle, settings: viewobject.allLayerSettings)
            }
        }
        let dotStroke = colorScheme == .dark
            ? UIColor(red: 46/255, green: 57/255, blue: 75/255, alpha: 1)
            : UIColor.white
        let labelHalo = colorScheme == .dark
            ? UIColor(red: 30/255, green: 41/255, blue: 59/255, alpha: 1)
            : UIColor(red: 237/255, green: 237/255, blue: 237/255, alpha: 1)
        let labelColor = NSExpression(
            format: "FUNCTION('#', 'stringByAppendingString:', \(colorScheme == .dark ? "contrastdarkmode" : "contrastlightmode"))"
        )
        let otherPredicate = NSPredicate(
            format: "route_type != 0 AND route_type != 1 AND route_type != 2 AND route_type != 3 AND route_type != 5 AND route_type != 6 AND route_type != 11 AND route_type != 12"
        )

        CircleStyleLayer(identifier: LayersPerCategory.TrajectoryIntercityRail.Livedots, source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [1: 0.8, 3: 2.0, 6: 2.3, 8: 3.5, 11: 5.5, 16: 9.5]))
            .strokeColor(dotStroke)
            .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                         stops: NSExpression(forConstantValue: [3: 0.6, 5: 0.7, 7: 0.8]))
            .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                           stops: NSExpression(forConstantValue: [4: 0.8, 7: 0.9, 11: 1.0]))
            .circleStrokeOpacity(1)
            .predicate(NSPredicate(format: "route_type == 2"))
            .minimumZoomLevel(1)
            .visible(viewobject.allLayerSettings.intercityrail.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.TrajectoryIntercityRail.Labeldots, source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-Medium"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: [6: 8, 9: 8, 11: 9.6, 13: 11.2, 16: 14.4]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2.4 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(NSPredicate(format: "route_type == 2"))
            .minimumZoomLevel(3)
            .visible(viewobject.allLayerSettings.intercityrail.visiblerealtimedots
                     && viewobject.allLayerSettings.intercityrail.labeltrajectories)

        CircleStyleLayer(identifier: LayersPerCategory.TrajectoryMetro.Livedots, source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [6: 2.5, 8: 2.3, 10: 3.0, 11: 4.5, 14: 6.5, 16: 10.5]))
            .strokeColor(dotStroke)
            .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                         stops: NSExpression(forConstantValue: [8: 0.8, 10: 1.2]))
            .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                           stops: NSExpression(forConstantValue: [7: 0.8, 9: 1.0]))
            .circleStrokeOpacity(1)
            .predicate(NSPredicate(format: "route_type == 1 OR route_type == 12"))
            .minimumZoomLevel(6)
            .visible(viewobject.allLayerSettings.localrail.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.TrajectoryMetro.Labeldots, source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-Medium"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: [6: 5, 9: 6.4, 10: 7.2, 11: 8, 13: 9.6, 15: 12.8]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2.4 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(NSPredicate(format: "route_type == 1 OR route_type == 12"))
            .minimumZoomLevel(6)
            .visible(viewobject.allLayerSettings.localrail.visiblerealtimedots
                     && viewobject.allLayerSettings.localrail.labeltrajectories)

        CircleStyleLayer(identifier: LayersPerCategory.TrajectoryTram.Livedots, source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [6: 1.5, 8: 2.0, 10: 3.5, 11: 4.0, 13: 5.5, 15: 4.5, 16: 9.5]))
            .strokeColor(dotStroke)
            .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                         stops: NSExpression(forConstantValue: [8: 0.5, 9: 0.6, 10: 1.0]))
            .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                           stops: NSExpression(forConstantValue: [7: 0.8, 9: 1.0]))
            .circleStrokeOpacity(1)
            .predicate(NSPredicate(format: "route_type == 0 OR route_type == 5"))
            .minimumZoomLevel(6.5)
            .visible(viewobject.allLayerSettings.localrail.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.TrajectoryTram.Labeldots, source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-Medium"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: [6: 4, 9: 6, 10: 7, 11: 6.4, 13: 8, 15: 11.2]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2.4 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(NSPredicate(format: "route_type == 0 OR route_type == 5"))
            .minimumZoomLevel(6.5)
            .visible(viewobject.allLayerSettings.localrail.visiblerealtimedots
                     && viewobject.allLayerSettings.localrail.labeltrajectories)

        CircleStyleLayer(identifier: LayersPerCategory.TrajectoryBus.Livedots, source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [7: 1.2, 8: 1.6, 9: 1.7, 10: 2.0, 16: 6.0]))
            .strokeColor(dotStroke)
            .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                         stops: NSExpression(forConstantValue: [9: railInFrame ? 0.4 : 0.8, 14: 1.0]))
            .circleOpacity(railInFrame ? 0.5 : 0.8)
            .circleStrokeOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                                 stops: NSExpression(forConstantValue: [7.9: 0.0, 8: 0.3, 9: 0.5, 13: 0.9]))
            .predicate(NSPredicate(format: "route_type == 3 OR route_type == 11"))
            .minimumZoomLevel(9)
            .visible(viewobject.allLayerSettings.bus.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.TrajectoryBus.Labeldots, source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-SemiBold"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: viewobject.allLayerSettings.bus.labelrealtimedots.headsign
                              ? [9: 4, 11: 5, 12: 7, 13: 9, 15: 11]
                              : [9: 5, 11: 7, 13: 10, 15: 13]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(NSPredicate(format: "route_type == 3 OR route_type == 11"))
            .minimumZoomLevel(9)
            .visible(viewobject.allLayerSettings.bus.visiblerealtimedots
                     && viewobject.allLayerSettings.bus.labeltrajectories)

        CircleStyleLayer(identifier: LayersPerCategory.TrajectoryOther.Livedots, source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [8: 5.0, 10: 6.0, 16: 8.0]))
            .strokeColor(dotStroke)
            .strokeWidth(1)
            .circleOpacity(0.5)
            .circleStrokeOpacity(1)
            .predicate(otherPredicate)
            .minimumZoomLevel(3)
            .visible(viewobject.allLayerSettings.other.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.TrajectoryOther.Labeldots, source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-Medium"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: [9: 8.5, 11: 13, 13: 16]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2.4 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(otherPredicate)
            .minimumZoomLevel(3)
            .visible(viewobject.allLayerSettings.other.visiblerealtimedots
                     && viewobject.allLayerSettings.other.labeltrajectories)

        CircleStyleLayer(identifier: LayersPerCategory.TrajectoryOther.Livedots + "_aerial", source: source)
            .color(expression: lineColorExpression)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [6: 1.5, 8: 2.0, 10: 3.5, 11: 4.0, 13: 5.5, 15: 4.5, 16: 9.5]))
            .strokeColor(dotStroke)
            .strokeWidth(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                         stops: NSExpression(forConstantValue: [8: 0.5, 9: 0.6, 10: 1.0]))
            .circleOpacity(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                           stops: NSExpression(forConstantValue: [7: 0.8, 9: 1.0]))
            .circleStrokeOpacity(1)
            .predicate(NSPredicate(format: "route_type == 6"))
            .minimumZoomLevel(6.5)
            .visible(viewobject.allLayerSettings.other.visiblerealtimedots)

        SymbolStyleLayer(identifier: LayersPerCategory.TrajectoryOther.Labeldots + "_aerial", source: source)
            .text(expression: NSExpression(format: "label_text"))
            .textFontNames(["Arimo-Medium"])
            .textFontSize(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                          stops: NSExpression(forConstantValue: [6: 4, 9: 6, 10: 7, 11: 6.4, 13: 8, 15: 11.2]))
            .textOffset(CGVector(dx: 0.8, dy: 0.1))
            .textColor(expression: labelColor)
            .textHaloColor(labelHalo)
            .textHaloWidth(colorScheme == .dark ? 2.4 : 1)
            .textHaloBlur(1)
            .textAllowsOverlap(false)
            .textAnchor("left")
            .predicate(NSPredicate(format: "route_type == 6"))
            .minimumZoomLevel(6.5)
            .visible(viewobject.allLayerSettings.other.visiblerealtimedots
                     && viewobject.allLayerSettings.other.labeltrajectories)
    }

    @MapViewContentBuilder
    var nearbyPinLayer: some StyleLayerCollection {
        let source = ShapeSource(identifier: NearbyPinMapCoordinator.sourceIdentifier) {
            if nearbyPinActive, let nearbyPinCoordinate {
                let feature = MLNPointFeature()
                feature.coordinate = nearbyPinCoordinate
                feature
            }
        }

        SymbolStyleLayer(
            identifier: NearbyPinMapCoordinator.layerIdentifier,
            source: source
        )
        .iconImage(UIImage(named: "map_marker_1")!)
        .iconAnchor("bottom")
        .iconAllowsOverlap(true)
        .iconScale(1)
        .renderAbove(.all)
        .visible(nearbyPinActive)
    }

    @MapViewContentBuilder
    var selectedStopLayer: some StyleLayerCollection {
        let source = ShapeSource(identifier: "selected-stop-context") {
            if let context = viewobject.selectedStopContext {
                let feature = MLNPointFeature()
                feature.coordinate = context.coordinate
                feature.attributes = ["name": context.name]
                feature
            }
        }

        CircleStyleLayer(identifier: "selected-stop-context-circle", source: source)
            .color(.catenaryBlue)
            .radius(interpolatedBy: .zoomLevel, curveType: .linear, parameters: nil,
                    stops: NSExpression(forConstantValue: [8: 5, 14: 8, 18: 11]))
            .strokeColor(.white)
            .strokeWidth(2)

        SymbolStyleLayer(identifier: "selected-stop-context-label", source: source)
            .text(expression: NSExpression(format: "name"))
            .textFontNames(["Arimo-Bold"])
            .textFontSize(12)
            .textOffset(CGVector(dx: 0, dy: 1.4))
            .textAnchor("top")
            .textColor(colorScheme == .dark ? .white : .black)
            .textHaloColor(colorScheme == .dark ? UIColor.black : UIColor.white)
            .textHaloWidth(1)
    }

    var body: some View {
        MapView(styleURL: styleURL, camera: $viewobject.camera) {
            shapeLayer
            stationFeaturesLayer
            stopsLayer
            wildfireMapLayers(
                fireFeatures: wildfireVM.fireFeatures,
                darkMode: colorScheme == .dark
            )
            realtimeLayer
            trajectoryLayer
            nearbyPinLayer
            selectedStopLayer
        }

        .unsafeMapViewControllerModifier { map in
            map.mapView.logoView.isHidden = true
            map.mapView.attributionButton.isHidden = true
            map.mapView.compassView.isHidden = true
            map.mapView.showsUserLocation = true
            nearbyPinMapCoordinator.install(on: map.mapView)
            nearbyPinMapCoordinator.updateContentInset(contentInset)
            nearbyPinMapCoordinator.updatePin(
                active: nearbyPinActive,
                coordinate: nearbyPinCoordinate
            )
            featureTapCoordinator.install(on: map.mapView, navigator: viewobject)
            featureTapCoordinator.updateLayerSettings(viewobject.allLayerSettings)

            let sourceCoordinator = featureTapCoordinator
            realtimeVM.onVehiclesChanged = { [weak sourceCoordinator] vehicles in
                sourceCoordinator?.updateRealtimeVehicles(vehicles)
            }
            trajectoryVM.onVehiclesChanged = { [weak sourceCoordinator] vehicles in
                sourceCoordinator?.updateTrajectoryVehicles(vehicles)
            }
            wildfireVM.onFeaturesChanged = { [weak sourceCoordinator] features in
                sourceCoordinator?.updateWildfireFeatures(features)
            }
        }
        .onMapViewProxyUpdate(updateMode: .onFinish, onViewProxyChanged: { proxy in
            Task { @MainActor in
                nearbyPinMapCoordinator.refreshScreenPoint()
                viewobject.currentRotation = proxy.direction
                viewobject.currZoom = proxy.zoomLevel
                viewobject.visibleCoordinateBounds = proxy.visibleCoordinateBounds
                realtimeVM.updateViewport(
                    bounds: proxy.visibleCoordinateBounds,
                    zoom: proxy.zoomLevel
                )
                trajectoryVM.updateViewport(
                    bounds: proxy.visibleCoordinateBounds,
                    zoom: proxy.zoomLevel
                )
            }
        })
        .task {
            realtimeVM.updateLayerSettings(viewobject.allLayerSettings)
            await realtimeVM.run()
        }
        .task {
            trajectoryVM.updateLayerSettings(viewobject.allLayerSettings)
            await trajectoryVM.run()
        }
        .task {
            await wildfireVM.run()
        }
        .onChange(of: viewobject.allLayerSettings) { _, settings in
            featureTapCoordinator.updateLayerSettings(settings)
            realtimeVM.updateLayerSettings(settings)
            trajectoryVM.updateLayerSettings(settings)
        }
        .onChange(of: viewobject.selectedStopContext) { _, context in
            featureTapCoordinator.updateSelectedStop(context)
        }
        .onDisappear {
            realtimeVM.stop()
            trajectoryVM.stop()
            wildfireVM.stop()
        }
        .mapUserAnnotationStyle(
            MapUserAnnotationStyle(
                approximateHaloBorderColor: .catenaryBlue,
                approximateHaloFillColor: .catenaryBlue,
                haloFillColor: .catenaryBlue,
                puckArrowFillColor: .catenaryBlue,
                puckFillColor: .white
            )
        )
        .ignoresSafeArea()
        
        
    }
    
}

#Preview {
    mapLibreView(
        locationManager: LocationManager(),
        nearbyPinMapCoordinator: NearbyPinMapCoordinator(),
        nearbyPinActive: false,
        nearbyPinCoordinate: nil,
        contentInset: .zero
    )
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



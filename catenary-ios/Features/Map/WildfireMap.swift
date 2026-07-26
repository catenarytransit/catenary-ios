//
//  WildfireMap.swift
//  catenary-ios
//
//  Swift/MapLibre port of catenary-compose's WildfireMap.kt.
//

import Combine
import CoreLocation
import Foundation
import MapLibre
import MapLibreSwiftDSL
import UIKit

enum WildfireMapIdentifiers {
    static let evacuationCASource = "wildfire-evacuation-ca"
    static let losAngelesEvacuationSource = "wildfire-los-angeles-evacuation"
    static let fireNamesSource = "firenames"
    static let modisSource = "wildfire-modis"
    static let viirsSource = "wildfire-viirs-nw"
}

private enum WildfireMapURLs {
    static let evacuationCA = URL(
        string: "https://fireboundscache.catenarymaps.org/data/ca_evacuations.json"
    )!
    static let losAngelesEvacuation = URL(
        string: "https://fireboundscache.catenarymaps.org/data/los_angeles_evac.json"
    )!
    static let watchDutyEvents = URL(
        string: "https://fireboundscache.catenarymaps.org/data/watchduty_events.json"
    )!
    static let modis = URL(
        string: "https://raw.githubusercontent.com/catenarytransit/fire-bounds-cache/refs/heads/main/data/modis.json"
    )!
    static let viirs = URL(
        string: "https://fireboundscache.catenarymaps.org/data/viirs_nw.json"
    )!
}

private struct WatchDutyFireData: Decodable {
    let name: String?
    let lat: Double?
    let lng: Double?
    let isActive: Bool?
    let data: WatchDutyFireDetails?
}

private struct WatchDutyFireDetails: Decodable {
    let acreage: Double?
    let containment: Int?
    let manualDeactivationStarted: Bool?
}

@MainActor
final class WildfireMapData: ObservableObject {
    private(set) var fireFeatures: [MLNPointFeature] = []

    var onFeaturesChanged: (([MLNPointFeature]) -> Void)? {
        didSet {
            onFeaturesChanged?(fireFeatures)
        }
    }

    func run() async {
        defer { stop() }

        while !Task.isCancelled {
            do {
                let (data, response) = try await URLSession.shared.data(
                    from: WildfireMapURLs.watchDutyEvents
                )
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let fires = try decoder.decode([WatchDutyFireData].self, from: data)
                publish(makeFireFeatures(from: fires))
            } catch is CancellationError {
                break
            } catch {
                print("WildfireMap: failed to fetch Watch Duty events: \(error)")
            }

            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                break
            }
        }
    }

    func stop() {
        publish([])
    }

    private func publish(_ features: [MLNPointFeature]) {
        fireFeatures = features
        onFeaturesChanged?(features)
    }

    private func makeFireFeatures(from fires: [WatchDutyFireData]) -> [MLNPointFeature] {
        fires.compactMap { fire in
            guard fire.isActive == true,
                  fire.data?.manualDeactivationStarted != true,
                  let latitude = fire.lat,
                  let longitude = fire.lng else {
                return nil
            }

            let acreage = fire.data?.acreage ?? 0
            let hectares = acreage * 0.4046
            let hectaresRounded = String(format: "%.1f", hectares)
            let name = fire.name ?? "Unknown Fire"

            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )
            feature.attributes = [
                "name": name,
                "acreage": String(acreage),
                "ha": hectares,
                "ha_rounded": hectaresRounded,
                "containment": String(fire.data?.containment ?? 0),
                "display_name": "\(name) \(hectaresRounded)ha",
                "icon_size": iconSizeCategory(forHectares: hectares)
            ]
            return feature
        }
    }

    private func iconSizeCategory(forHectares hectares: Double) -> String {
        switch hectares {
        case ..<100:
            "small"
        case ..<1_000:
            "medium"
        case ..<5_000:
            "large"
        default:
            "very-large"
        }
    }
}

@MapViewContentBuilder
func wildfireMapLayers(
    fireFeatures: [MLNPointFeature],
    darkMode: Bool
) -> some StyleLayerCollection {
    let evacuationCASource = MLNShapeSource(
        identifier: WildfireMapIdentifiers.evacuationCASource,
        url: WildfireMapURLs.evacuationCA,
        options: nil
    )
    let losAngelesEvacuationSource = MLNShapeSource(
        identifier: WildfireMapIdentifiers.losAngelesEvacuationSource,
        url: WildfireMapURLs.losAngelesEvacuation,
        options: nil
    )
    let modisSource = MLNShapeSource(
        identifier: WildfireMapIdentifiers.modisSource,
        url: WildfireMapURLs.modis,
        options: nil
    )
    let viirsSource = MLNShapeSource(
        identifier: WildfireMapIdentifiers.viirsSource,
        url: WildfireMapURLs.viirs,
        options: nil
    )
    let fireNamesSource = ShapeSource(identifier: WildfireMapIdentifiers.fireNamesSource) {
        for feature in fireFeatures {
            feature
        }
    }

    let evacuationTextColor = darkMode
        ? UIColor(red: 0xCC / 255, green: 0xAA / 255, blue: 0xAA / 255, alpha: 1)
        : UIColor(red: 0xCC / 255, green: 0, blue: 0, alpha: 1)
    let fireTextColor = darkMode
        ? UIColor(red: 1, green: 0xAA / 255, blue: 0xAA / 255, alpha: 1)
        : UIColor(red: 0xAA / 255, green: 0, blue: 0, alpha: 1)
    let labelHaloColor = darkMode
        ? UIColor(red: 15 / 255, green: 23 / 255, blue: 42 / 255, alpha: 0.85)
        : UIColor(white: 1, alpha: 0.85)
    let evacuationFill = UIColor(red: 0xDD / 255, green: 0x33 / 255, blue: 0, alpha: 1)
    let orangeFire = UIColor(red: 1, green: 0x75 / 255, blue: 0x1F / 255, alpha: 1)
    let redFire = UIColor(red: 1, green: 0x1A / 255, blue: 0x1A / 255, alpha: 1)

    FillStyleLayer(identifier: "evacuation_ca_fire_bounds", source: evacuationCASource)
        .fillColor(evacuationFill)
        .fillOpacity(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                9: 0.3,
                12: 0.2,
                15: 0.2,
                16: 0.15
            ])
        )
        .minimumZoomLevel(5)

    SymbolStyleLayer(identifier: "evacuation_ca_fire_txt", source: evacuationCASource)
        .text(expression: NSExpression(format: "zone_status"))
        .textFontNames(["Arimo-Bold"])
        .textFontSize(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [7: 8, 9: 13])
        )
        .textColor(evacuationTextColor)
        .textHaloColor(labelHaloColor)
        .textHaloWidth(0.8)
        .minimumZoomLevel(6)

    FillStyleLayer(
        identifier: "los_angeles_city_fire_evac_bounds",
        source: losAngelesEvacuationSource
    )
    .fillColor(evacuationFill)
    .fillOpacity(
        interpolatedBy: .zoomLevel,
        curveType: .linear,
        parameters: nil,
        stops: NSExpression(forConstantValue: [
            9: 0.2,
            12: 0.1,
            15: 0.1
        ])
    )
    .minimumZoomLevel(5)

    SymbolStyleLayer(
        identifier: "los_angeles_city_fire_evac_txt",
        source: losAngelesEvacuationSource
    )
    .text(expression: NSExpression(format: "Label"))
    .textFontNames(["Arimo-Bold"])
    .textFontSize(
        interpolatedBy: .zoomLevel,
        curveType: .linear,
        parameters: nil,
        stops: NSExpression(forConstantValue: [7: 8, 9: 12.5])
    )
    .textColor(evacuationTextColor)
    .textHaloColor(labelHaloColor)
    .textHaloWidth(0.8)
    .minimumZoomLevel(6)

    SymbolStyleLayer(identifier: "firenameslabelwd", source: fireNamesSource)
        .iconImage(
            featurePropertyNamed: "icon_size",
            mappings: [
                "small": wildfireFlameImage(pointSize: 12),
                "medium": wildfireFlameImage(pointSize: 16),
                "large": wildfireFlameImage(pointSize: 20),
                "very-large": wildfireFlameImage(pointSize: 24)
            ],
            default: wildfireFlameImage(pointSize: 12)
        )
        .iconAllowsOverlap(true)
        .text(expression: NSExpression(format: "display_name"))
        .textOffset(CGVector(dx: 0, dy: 1.5))
        .textAnchor("top")
        .textFontNames(["Arimo-Medium"])
        .textFontSize(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [6: 6, 12: 14])
        )
        .textAllowsOverlap(true)
        .textColor(fireTextColor)
        .textHaloColor(labelHaloColor)
        .textHaloWidth(1)
        .minimumZoomLevel(5.5)

    CircleStyleLayer(identifier: "modis", source: modisSource)
        .color(expression: NSExpression(
            forMLNInterpolating: NSExpression(forKeyPath: "BRIGHTNESS"),
            curveType: MLNExpressionInterpolationMode.linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                310.64: orangeFire,
                508.63: redFire
            ])
        ))
        .circleOpacity(expression: NSExpression(
            forMLNInterpolating: NSExpression(forKeyPath: "BRIGHTNESS"),
            curveType: MLNExpressionInterpolationMode.linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                310.64: 0.3,
                508.63: 0.5
            ])
        ))
        .radius(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                5: 1,
                9: 5,
                12: 15,
                15: 22,
                22: 50
            ])
        )
        .minimumZoomLevel(5)

    CircleStyleLayer(identifier: "viirs_nw", source: viirsSource)
        .color(expression: NSExpression(
            forMLNInterpolating: NSExpression(forKeyPath: "frp"),
            curveType: MLNExpressionInterpolationMode.linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                3: orangeFire,
                100: redFire
            ])
        ))
        .circleOpacity(expression: NSExpression(
            forMLNInterpolating: NSExpression(forKeyPath: "frp"),
            curveType: MLNExpressionInterpolationMode.linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                3: 0.1,
                10: 0.3,
                100: 0.4
            ])
        ))
        .radius(
            interpolatedBy: .zoomLevel,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                5: 0.3,
                9: 1.6,
                12: 5,
                15: 13,
                22: 16
            ])
        )
        .minimumZoomLevel(5)
}

private func wildfireFlameImage(pointSize: CGFloat) -> UIImage {
    let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
    let image = UIImage(systemName: "flame.fill", withConfiguration: configuration) ?? UIImage()
    return image.withTintColor(
        UIColor(red: 1, green: 0x33 / 255, blue: 0, alpha: 1),
        renderingMode: .alwaysOriginal
    )
}

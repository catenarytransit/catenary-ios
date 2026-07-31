//
//  LayerSettings.swift
//  catenary-ios
//

import Foundation

struct AllLayerSettings: Codable, Equatable {
    var bus: LayerCategorySettings = LayerCategorySettings()
    var localrail: LayerCategorySettings = LayerCategorySettings()
    var intercityrail: LayerCategorySettings = LayerCategorySettings(labelrealtimedots: LabelSettings(trip: true))
    var other: LayerCategorySettings = LayerCategorySettings()
    var more: MoreSettings = MoreSettings()

    subscript(index: Int) -> LayerCategorySettings? {
        switch index {
        case 1: return intercityrail
        case 2: return localrail
        case 3: return bus
        case 4: return other
        default: return nil
        }
    }

    subscript(name: String) -> LayerCategorySettings? {
        switch name {
        case "Rail": return intercityrail
        case "Metro/Tram": return localrail
        case "Bus": return bus
        case "Other": return other
        default: return nil
        }
    }
}

struct LayerCategorySettings: Codable, Equatable {
    var visiblerealtimedots: Bool = true
    var labeltrajectories: Bool = false
    var labelshapes: Bool = true
    var stops: Bool = true
    var shapes: Bool = true
    var labelstops: Bool = true
    var labelrealtimedots: LabelSettings = LabelSettings()
}

struct LabelSettings: Codable, Equatable {
    var route: Bool = true
    var trip: Bool = false
    var vehicle: Bool = false
    var headsign: Bool = false
    var direction: Bool = false
    var speed: Bool = false
    var occupancy: Bool = true
    var delay: Bool = true
}

struct MoreSettings: Codable, Equatable {
    var foamermode: FoamermodeSettings = FoamermodeSettings()
    var showstationentrances: Bool = true
    var showstationart: Bool = false
    var showbikelanes: Bool = false
    var showcoords: Bool = false
}

struct FoamermodeSettings: Codable, Equatable {
    var infra: Bool = false
    var maxspeed: Bool = false
    var signalling: Bool = false
    var electrification: Bool = false
    var gauge: Bool = false
    var dummy: Bool = true
}

enum LayerSettingsPersistence {
    private static let defaultsKey = "allLayerSettings.v1"

    static func load(from defaults: UserDefaults = .standard) -> AllLayerSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(AllLayerSettings.self, from: data) else {
            return AllLayerSettings()
        }
        return settings
    }

    static func save(_ settings: AllLayerSettings, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

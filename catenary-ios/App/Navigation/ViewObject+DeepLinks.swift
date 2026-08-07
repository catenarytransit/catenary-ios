//
//  ViewObject+DeepLinks.swift
//  catenary-ios
//

import Foundation

private struct CatenaryDeepLinkQuery {
    let components: URLComponents

    func value(_ names: String...) -> String? {
        for name in names {
            if let value = components.queryItems?.first(where: { $0.name == name })?.value,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func displayValue(_ names: String...) -> String? {
        for name in names {
            if let value = value(name) {
                return value.replacingOccurrences(of: "+", with: " ")
            }
        }
        return nil
    }

    var selectedTimeEpochSeconds: Int64? {
        guard value("is_now")?.lowercased() == "false" else { return nil }
        return value("time").flatMap(Int64.init)
    }
}

extension viewObject {
    func openDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let query = CatenaryDeepLinkQuery(components: components)

        if components.scheme?.lowercased() == "https",
           components.host?.lowercased() == "maps.catenarymaps.org",
           query.value("page") != nil {
            openCatenaryMapsLink(query)
            return
        }

        openLegacyDeepLink(query)
    }

    private func openCatenaryMapsLink(_ query: CatenaryDeepLinkQuery) {
        switch query.value("page") {
        case "route":
            guard let chateauID = query.value("chateau"),
                  let routeID = query.value("route", "route_id") else { return }
            push(.route(chateauID: chateauID, routeID: routeID))

        case "stop":
            guard let chateauID = query.value("chateau"),
                  let stopID = query.value("stop", "stop_id") else { return }
            push(.stop(
                chateauID: chateauID,
                stopID: stopID,
                timeEpochSeconds: query.selectedTimeEpochSeconds
            ))

        case "trip":
            guard let chateauID = query.value("chateau") else { return }
            push(.singleTrip(
                chateauID: chateauID,
                tripID: query.value("trip", "trip_id"),
                routeID: query.value("route", "route_id"),
                startTime: query.value("start_time"),
                startDate: query.value("start_date"),
                vehicleID: query.value("vehicle", "vehicle_id"),
                routeType: query.value("route_type").flatMap(Int.init)
            ))

        case "osm_departures", "osm_station":
            guard let osmStationID = query.value("osm_id", "osm_station_id") else { return }
            push(.osmStation(
                osmStationID: osmStationID,
                stationName: query.displayValue("name", "station_name"),
                modeType: query.value("mode", "mode_type"),
                latitude: query.value("lat").flatMap(Double.init),
                longitude: query.value("lon").flatMap(Double.init),
                timeEpochSeconds: query.selectedTimeEpochSeconds
            ))

        case "block":
            guard let chateauID = query.value("chateau"),
                  let blockID = query.value("block", "block_id"),
                  let serviceDate = query.value("service_date") else { return }
            push(.block(chateauID: chateauID, blockID: blockID, serviceDate: serviceDate))

        case "vehicle_history":
            guard let chateauID = query.value("chateau"),
                  let vehicleID = query.value("vehicle", "vehicle_id") else { return }
            push(.vehicleHistory(
                chateauID: chateauID,
                vehicleID: vehicleID,
                routeID: query.value("route", "route_id")
            ))

        case "osm_item":
            guard let osmID = query.value("osm_id"),
                  let osmClass = query.value("osm_class") else { return }
            push(.osmItem(
                osmID: osmID,
                osmClass: osmClass,
                osmType: query.value("osm_type")
            ))

        case "nearby", "nearby_departures":
            guard let latitude = query.value("lat").flatMap(Double.init),
                  let longitude = query.value("lon").flatMap(Double.init) else { return }
            push(.nearbyDepartures(
                // The web URL schema does not currently serialize chateau for nearby.
                chateauID: query.value("chateau") ?? "",
                latitude: latitude,
                longitude: longitude
            ))

        default:
            break
        }
    }

    private func openLegacyDeepLink(_ query: CatenaryDeepLinkQuery) {
        switch query.value("screen") {
        case "route":
            guard let chateauID = query.value("chateau"), let routeID = query.value("route_id") else { return }
            push(.route(chateauID: chateauID, routeID: routeID))
        case "stop":
            guard let chateauID = query.value("chateau"), let stopID = query.value("stop_id") else { return }
            push(.stop(chateauID: chateauID, stopID: stopID))
        case "trip":
            guard let chateauID = query.value("chateau") else { return }
            push(.singleTrip(
                chateauID: chateauID,
                tripID: query.value("trip_id"),
                routeID: query.value("route_id"),
                startTime: query.value("start_time"),
                startDate: query.value("start_date"),
                vehicleID: query.value("vehicle_id"),
                routeType: query.value("route_type").flatMap(Int.init)
            ))
        case "osm_station":
            guard let osmStationID = query.value("osm_station_id") else { return }
            push(.osmStation(
                osmStationID: osmStationID,
                stationName: query.displayValue("station_name"),
                modeType: query.value("mode_type"),
                latitude: query.value("lat").flatMap(Double.init),
                longitude: query.value("lon").flatMap(Double.init)
            ))
        default:
            break
        }
    }
}

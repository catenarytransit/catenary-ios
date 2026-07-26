//
//  ViewObject+DeepLinks.swift
//  catenary-ios
//

import Foundation

extension viewObject {
    func openDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        func query(_ name: String) -> String? {
            components.queryItems?.first(where: { $0.name == name })?.value
        }

        switch query("screen") {
        case "route":
            guard let chateauID = query("chateau"), let routeID = query("route_id") else { return }
            push(.route(chateauID: chateauID, routeID: routeID))
        case "stop":
            guard let chateauID = query("chateau"), let stopID = query("stop_id") else { return }
            push(.stop(chateauID: chateauID, stopID: stopID))
        case "trip":
            guard let chateauID = query("chateau") else { return }
            push(.singleTrip(
                chateauID: chateauID,
                tripID: query("trip_id"),
                routeID: query("route_id"),
                startTime: query("start_time"),
                startDate: query("start_date"),
                vehicleID: query("vehicle_id"),
                routeType: query("route_type").flatMap { Int($0) }
            ))
        case "osm_station":
            guard let osmStationID = query("osm_station_id") else { return }
            push(.osmStation(
                osmStationID: osmStationID,
                stationName: query("station_name"),
                modeType: query("mode_type"),
                latitude: query("lat").flatMap { Double($0) },
                longitude: query("lon").flatMap { Double($0) }
            ))
        default:
            break
        }
    }
}

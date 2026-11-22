import Foundation

struct JourneyTripEndpoint: Codable, Hashable, Sendable {
    let stopID: String
    let sequence: Int?
    let time: Int64
}

struct JourneyTripSegment: Codable, Hashable, Sendable {
    let from: JourneyTripEndpoint
    let to: JourneyTripEndpoint

    var identity: String {
        "\(from.stopID)|\(from.sequence.map(String.init) ?? "")|\(from.time)|\(to.stopID)|\(to.sequence.map(String.init) ?? "")|\(to.time)"
    }
}

struct JourneyStopPresentation: Equatable {
    let active: Bool
    let endpoint: Bool
    let incomingActive: Bool
    let outgoingActive: Bool
}

struct JourneyTripRange: Equatable {
    let from: Int
    let to: Int

    func stop(_ index: Int) -> JourneyStopPresentation {
        JourneyStopPresentation(active: (from...to).contains(index), endpoint: index == from || index == to,
            incomingActive: index > from && index <= to, outgoingActive: index >= from && index < to)
    }

    static func resolve(stops: [SingleTripStopTime], segment: JourneyTripSegment?) -> Self? {
        guard let segment else { return nil }
        func find(_ endpoint: JourneyTripEndpoint, arrival: Bool) -> Int? {
            if let sequence = endpoint.sequence,
               let index = stops.firstIndex(where: { $0.stopID == endpoint.stopID && $0.gtfsStopSequence == sequence }) {
                return index
            }
            return stops.enumerated().compactMap { index, stop -> (Int, Double)? in
                guard stop.stopID == endpoint.stopID,
                      let time = (arrival ? stop.scheduledArrivalTimeUnixSeconds : stop.scheduledDepartureTimeUnixSeconds)
                        ?? stop.scheduledDepartureTimeUnixSeconds ?? stop.scheduledArrivalTimeUnixSeconds
                        ?? stop.interpolatedStoptimeUnixSeconds else { return nil }
                return (index, abs(Double(time) - Double(endpoint.time)))
            }.min { $0.1 < $1.1 }?.0
        }
        guard let from = find(segment.from, arrival: false), let to = find(segment.to, arrival: true),
              to >= from else { return nil }
        return Self(from: from, to: to)
    }
}

extension DirectionsLeg {
    var singleTripInfo: SingleTripSelection? {
        func present(_ value: String?) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        guard !street, let chateau = present(chateau), let tripID = present(tripId),
              let date = present(tripStartDate), let fromID = present(from?.stopId), let toID = present(to?.stopId),
              let departure = directionsDate(startTime), let arrival = directionsDate(endTime) else { return nil }
        return SingleTripSelection(chateauID: chateau, tripID: tripID, routeID: routeId,
            startTime: tripStartTime, startDate: date, vehicleID: nil, routeType: routeType,
            journeySegment: JourneyTripSegment(
                from: JourneyTripEndpoint(stopID: fromID, sequence: fromStopSequence, time: Int64(departure.timeIntervalSince1970)),
                to: JourneyTripEndpoint(stopID: toID, sequence: toStopSequence, time: Int64(arrival.timeIntervalSince1970))))
    }
}

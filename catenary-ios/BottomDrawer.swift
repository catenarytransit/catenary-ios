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
    let sheetHeight: CGFloat
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var searchViewModel: SearchViewModel
    @Binding var nearbyPinActive: Bool
    @Binding var nearbyPinCoordinate: CLLocationCoordinate2D?
    @EnvironmentObject var viewObject: viewObject
    @FocusState var isFocused: Bool

    var body: some View {
        Group {
            if let destination = viewObject.currentStackItem {
                CatenaryStackDestinationView(
                    destination: destination,
                    locationManager: locationManager,
                    nearbyPinActive: $nearbyPinActive,
                    nearbyPinCoordinate: $nearbyPinCoordinate
                )
            } else if isFocused {
                CatenarySearchResultsView(
                    viewModel: searchViewModel,
                    onCypressClick: selectCypress,
                    onStopClick: selectStop,
                    onRouteClick: selectRoute,
                    onOsmStationClick: selectOsmStation
                )
            } else {
                NearbyDeparturesView(
                    locationManager: locationManager,
                    pinActive: $nearbyPinActive,
                    pickedCoordinate: $nearbyPinCoordinate
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack {
                if viewObject.currentStackItem == nil {
                    if selectedDetent == .large || viewObject.isVisible {
                        CatenarySearchBar(
                            query: $viewObject.searchText,
                            focus: $isFocused,
                            onSettingsClick: openSettings
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 18)
                        .frame(height: 80)
                        .padding(.top, 12)
                    } else if selectedDetent != .height(80) {
                        Spacer()
                            .frame(height: 0.5 * max(160 - (viewObject.largeDetentHeight - sheetHeight), 0))
                    }
                } else {
                    StackNavigationControls(
                        canGoBack: !viewObject.catenaryStack.isEmpty,
                        onBack: { viewObject.pop() },
                        onHome: { viewObject.home() }
                    )
                    .padding(.horizontal, 18)
                    .frame(height: 64)
                    .padding(.top, 12)
                }
            }
            .ignoresSafeArea(.keyboard)
        }
        .onChange(of: selectedDetent) { _, detent in
            guard detent == .large else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard selectedDetent == .large,
                      viewObject.isSearchFocusing,
                      viewObject.currentStackItem == nil else { return }
                isFocused = true
                viewObject.isSearchFocusing = false
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                viewObject.isSearchFocusing = false
            }
        }
    }

    private func selectCypress(_ feature: SearchCypressFeature) {
        guard let coordinate = feature.coordinate else { return }
        finishSearch()
        viewObject.camera = .center(coordinate, zoom: 16)
        selectedDetent = .height(350)
    }

    private func selectStop(_ ranking: SearchStopRanking) {
        guard let chateauID = ranking.chateau, let stopID = ranking.gtfsID else { return }
        finishSearch()
        viewObject.push(.stop(chateauID: chateauID, stopID: stopID))
    }

    private func selectRoute(_ ranking: SearchRouteRanking) {
        guard let chateauID = ranking.chateau, let routeID = ranking.gtfsID else { return }
        finishSearch()
        viewObject.push(.route(chateauID: chateauID, routeID: routeID))
    }

    private func selectOsmStation(_ station: SearchOsmStationResult) {
        guard let osmStationID = station.osmID else { return }
        finishSearch()
        viewObject.push(
            .osmStation(
                osmStationID: osmStationID,
                stationName: station.name,
                modeType: station.modeType,
                latitude: station.point?.y,
                longitude: station.point?.x
            )
        )
    }

    private func openSettings() {
        finishSearch()
        viewObject.push(.settings)
    }

    private func finishSearch() {
        isFocused = false
        viewObject.isSearchFocusing = false
        viewObject.searchText = ""
    }
}

private struct StackNavigationControls: View {
    let canGoBack: Bool
    let onBack: () -> Void
    let onHome: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(!canGoBack)

            Button(action: onHome) {
                Image(systemName: "house.fill")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)

            Spacer()
        }
    }
}

private struct CatenaryStackDestinationView: View {
    let destination: CatenaryStackItem
    @ObservedObject var locationManager: LocationManager
    @Binding var nearbyPinActive: Bool
    @Binding var nearbyPinCoordinate: CLLocationCoordinate2D?
    @EnvironmentObject private var viewObject: viewObject

    @ViewBuilder
    var body: some View {
        switch destination {
        case .stop, .osmStation:
            StationDeparturesScreen(destination: destination)
                .id(destination.stopScreenIdentity)

        case let .singleTrip(chateauID, tripID, routeID, startTime, startDate, vehicleID, routeType):
            SingleTripScreen(
                selection: SingleTripSelection(
                    chateauID: chateauID,
                    tripID: tripID,
                    routeID: routeID,
                    startTime: startTime,
                    startDate: startDate,
                    vehicleID: vehicleID,
                    routeType: routeType
                )
            )
            .id(destination.id)

        case let .vehicleHistory(chateauID, vehicleID, routeID):
            VehicleHistoryScreen(
                selection: VehicleHistorySelection(
                    chateauID: chateauID,
                    vehicleID: vehicleID,
                    routeID: routeID
                )
            )
            .id(destination.id)

        case let .route(chateauID, routeID):
            RouteScreen(chateauID: chateauID, routeID: routeID)
                .id(destination.id)

        case let .nearbyDepartures(_, latitude, longitude):
            NearbyDeparturesView(
                locationManager: locationManager,
                fixedOrigin: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                pinActive: $nearbyPinActive,
                pickedCoordinate: $nearbyPinCoordinate
            )
            .id(destination.id)

        case let .mapSelectionScreen(options):
            MapOverlappingSelectionScreen(options: options)

        case .settings:
            SettingsScreen()

        default:
            // Vehicle selection, block, and OSM item screens remain placeholders.
            ScrollView {
                StackDestinationSummary(destination: destination)
                    .padding()
            }
        }
    }
}

private struct StackDestinationSummary: View {
    let destination: CatenaryStackItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.largeTitle.bold())
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.key(row.0))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(row.1)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        switch destination {
        case .singleTrip: return L10n.string("Trip")
        case .vehicleSelected: return L10n.string("Vehicle")
        case .vehicleHistory: return L10n.string("Vehicle History")
        case .route: return L10n.string("Route")
        case .stop: return L10n.string("Stop")
        case .nearbyDepartures: return L10n.string("Nearby departures")
        case .mapSelectionScreen: return L10n.string("Selection")
        case .settings: return L10n.string("Settings")
        case .block: return L10n.string("Block")
        case .osmItem: return L10n.string("Map item")
        case let .osmStation(_, stationName, _, _, _, _):
            return stationName ?? L10n.string("Station")
        }
    }

    private var rows: [(String, String)] {
        switch destination {
        case let .singleTrip(chateauID, tripID, routeID, startTime, startDate, vehicleID, routeType):
            return compactRows([
                ("Chateau", chateauID), ("Trip", tripID), ("Route", routeID),
                ("Start time", startTime), ("Start date", startDate),
                ("Vehicle", vehicleID), ("Route type", routeType.map { String($0) })
            ])
        case let .vehicleSelected(chateauID, vehicleID, gtfsID):
            return compactRows([("Chateau", chateauID), ("Vehicle", vehicleID), ("GTFS feed", gtfsID)])
        case let .vehicleHistory(chateauID, vehicleID, routeID):
            return compactRows([
                ("Chateau", chateauID), ("Vehicle", vehicleID), ("Route", routeID)
            ])
        case let .route(chateauID, routeID):
            return [("Chateau", chateauID), ("Route", routeID)]
        case let .stop(chateauID, stopID, time):
            return compactRows([("Chateau", chateauID), ("Stop", stopID), ("Time", time.map { String($0) })])
        case let .nearbyDepartures(chateauID, latitude, longitude):
            return [("Chateau", chateauID), ("Latitude", String(latitude)), ("Longitude", String(longitude))]
        case let .block(chateauID, blockID, serviceDate):
            return [("Chateau", chateauID), ("Block", blockID), ("Service date", serviceDate)]
        case let .osmItem(osmID, osmClass, osmType):
            return compactRows([("OSM ID", osmID), ("Class", osmClass), ("Type", osmType)])
        case let .osmStation(osmStationID, _, modeType, latitude, longitude, time):
            return compactRows([
                ("OSM station", osmStationID), ("Mode", modeType),
                ("Latitude", latitude.map { String($0) }), ("Longitude", longitude.map { String($0) }),
                ("Time", time.map { String($0) })
            ])
        case .mapSelectionScreen, .settings:
            return []
        }
    }

    private func compactRows(_ rows: [(String, String?)]) -> [(String, String)] {
        rows.compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
    }
}

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
    let collapsedDrawerHeight: CGFloat?
    @ObservedObject var locationManager: LocationManager
    let searchViewModel: SearchViewModel
    let focusRequest: Int
    let showsSearchBarWhenInactive: Bool
    @Binding var nearbyPinActive: Bool
    @Binding var nearbyPinCoordinate: CLLocationCoordinate2D?
    @EnvironmentObject var viewObject: viewObject
    @FocusState private var isFocused: Bool
    @State private var isSearchActive = false

    var body: some View {
        Group {
            if let destination = viewObject.currentStackItem {
                CatenaryStackDestinationView(
                    destination: destination,
                    locationManager: locationManager,
                    nearbyPinActive: $nearbyPinActive,
                    nearbyPinCoordinate: $nearbyPinCoordinate
                )
            } else {
                ZStack {
                    NearbyDeparturesView(
                        locationManager: locationManager,
                        drawerHeight: sheetHeight,
                        isDrawerCollapsed: selectedDetent == .height(80),
                        collapsedDrawerHeight: collapsedDrawerHeight,
                        pinActive: $nearbyPinActive,
                        pickedCoordinate: $nearbyPinCoordinate
                    )
                    .opacity(isSearchActive ? 0 : 1)
                    .allowsHitTesting(!isSearchActive)
                    .accessibilityHidden(isSearchActive)

                    if isSearchActive {
                        CatenarySearchResultsView(
                            viewModel: searchViewModel,
                            onCypressClick: selectCypress,
                            onStopClick: selectStop,
                            onRouteClick: selectRoute,
                            onOsmStationClick: selectOsmStation,
                            onRecentClick: selectRecent
                        )
                        .transition(.opacity)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack {
                if viewObject.currentStackItem == nil {
                    if selectedDetent == .large,
                       showsSearchBarWhenInactive || isSearchActive {
                        CatenarySearchBar(
                            viewModel: searchViewModel,
                            focus: $isFocused,
                            isActive: isSearchActive,
                            onQueryChange: performSearch,
                            onClose: finishSearch,
                            onSettingsClick: openSettings
                        )
                        .padding(.horizontal, 18)
                        .frame(height: 80)
                        .padding(.top, 12)
                    } else if selectedDetent == .large {
                        Spacer()
                            .frame(height: 28)
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
                    .frame(height: 48)
                    .padding(.top, 6)
                }
            }
            .ignoresSafeArea(.keyboard)
        }
        .task(id: focusRequest) {
            guard focusRequest > 0,
                  selectedDetent == .large,
                  viewObject.currentStackItem == nil else { return }

            // Activate the search content immediately, then give SwiftUI one
            // render pass to install the TextField before making it first responder.
            // This opens the keyboard with the drawer expansion instead of 350 ms later.
            isSearchActive = true
            await Task.yield()

            guard selectedDetent == .large,
                  viewObject.currentStackItem == nil else { return }
            isFocused = true
        }
        .catenaryOnChange(of: selectedDetent) { _, detent in
            if detent != .large, isSearchActive {
                finishSearch()
            }
        }
        .catenaryOnChange(of: isFocused) { _, focused in
            if focused {
                isSearchActive = true
            }
        }
        .catenaryOnChange(of: viewObject.catenaryStack) { _, stack in
            if !stack.isEmpty {
                finishSearch()
            }
        }
    }

    private func performSearch(_ query: String) {
        searchViewModel.search(
            query: query,
            userLocation: locationManager.lastKnownLocation,
            mapCenter: viewObject.visibleCoordinateBounds.catenarySearchCenter,
            mapZoom: viewObject.currZoom
        )
    }

    private func selectCypress(_ feature: SearchCypressFeature) {
        guard let coordinate = feature.coordinate else { return }
        finishSearch()
        if let reference = OSMObjectReference.fromCypressIdentifier(feature.properties?.id) {
            viewObject.push(.osmItem(
                osmID: reference.osmID,
                osmClass: reference.osmClass,
                osmType: feature.properties?.layer,
                name: feature.properties?.name ?? feature.properties?.names?["default"],
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ))
        } else {
            viewObject.camera = .center(coordinate, zoom: 16)
            selectedDetent = .height(350)
        }
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

    private func selectRecent(_ item: SearchHistoryItem) {
        switch item.kind {
        case .osmItem:
            guard let osmID = item.osmStationID,
                  let osmClass = item.osmClass else { return }
            finishSearch()
            viewObject.push(.osmItem(
                osmID: osmID, osmClass: osmClass, osmType: item.osmType,
                name: item.title, latitude: item.latitude, longitude: item.longitude
            ))

        case .cypress:
            guard let latitude = item.latitude, let longitude = item.longitude else { return }
            finishSearch()
            viewObject.camera = .center(
                CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                zoom: 16
            )
            selectedDetent = .height(350)

        case .stop:
            guard let chateauID = item.chateauID, let stopID = item.gtfsID else { return }
            finishSearch()
            viewObject.push(.stop(chateauID: chateauID, stopID: stopID))

        case .route:
            guard let chateauID = item.chateauID, let routeID = item.gtfsID else { return }
            finishSearch()
            viewObject.push(.route(chateauID: chateauID, routeID: routeID))

        case .osmStation:
            guard let osmStationID = item.osmStationID else { return }
            finishSearch()
            viewObject.push(
                .osmStation(
                    osmStationID: osmStationID,
                    stationName: item.title,
                    modeType: item.modeType,
                    latitude: item.latitude,
                    longitude: item.longitude
                )
            )
        }
    }

    private func openSettings() {
        finishSearch()
        viewObject.push(.settings)
    }

    private func finishSearch() {
        isFocused = false
        isSearchActive = false
        searchViewModel.reset()
    }
}

private struct StackNavigationControls: View {
    let canGoBack: Bool
    let onBack: () -> Void
    let onHome: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            compactButton("chevron.backward", label: "Back", action: onBack)
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.35)

            compactButton("house.fill", label: "Home", action: onHome)
            Spacer(minLength: 0)
        }
    }

    private func compactButton(
        _ systemName: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                // Keep the visible circle slightly smaller than the hit target,
                // without the automatic padding of a bordered button.
                .frame(width: 38, height: 38)
                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                }
                // Preserve at least a 48pt touch target around each control.
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
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

        case let .mapSelectionScreen(options, lookup):
            MapOverlappingSelectionScreen(options: options, routeLookup: lookup)

        case .settings:
            SettingsScreen()

        case let .osmItem(osmID, osmClass, osmType, name, latitude, longitude):
            OSMItemScreen(
                osmID: osmID,
                osmClass: osmClass,
                osmType: osmType,
                previewName: name,
                latitude: latitude,
                longitude: longitude
            )
            .id(destination.id)

        default:
            // Vehicle selection and block screens remain placeholders.
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
        case let .osmItem(osmID, osmClass, osmType, _, _, _):
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

//
//  ContentView.swift
//  catenary-ios
//
//

import MapLibre
import MapLibreSwiftDSL
import CoreLocationUI
import SwiftUI
import CoreLocation
import MapLibreSwiftUI
import UIKit

final class FloatingWindow: UIWindow {
    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        self.windowLevel = .statusBar + 5   // ↑ above sheets
        self.backgroundColor = .clear
        self.isHidden = false
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
}

private struct NativeSheetLeadingAnchor: UIViewControllerRepresentable {
    @Binding var sheetWidth: CGFloat

    func makeUIViewController(context: Context) -> NativeSheetLeadingAnchorController {
        let controller = NativeSheetLeadingAnchorController()
        configure(controller)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: NativeSheetLeadingAnchorController,
        context: Context
    ) {
        configure(uiViewController)
        uiViewController.scheduleUpdate()
    }

    private func configure(_ controller: NativeSheetLeadingAnchorController) {
        let widthBinding = $sheetWidth
        controller.onSheetWidthChange = { width in
            guard abs(widthBinding.wrappedValue - width) > 0.5 else { return }
            widthBinding.wrappedValue = width
        }
    }
}

private final class NativeSheetLeadingAnchorController: UIViewController {
    var onSheetWidthChange: ((CGFloat) -> Void)?
    private var delayedUpdate: DispatchWorkItem?

    override func loadView() {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        scheduleUpdate()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scheduleUpdate()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        scheduleUpdate()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        scheduleUpdate()
    }

    deinit {
        delayedUpdate?.cancel()
    }

    func scheduleUpdate() {
        applySheetPosition()

        delayedUpdate?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applySheetPosition()
        }
        delayedUpdate = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func applySheetPosition() {
        guard let sheetController = containingPresentedController,
              let presentationController = sheetController.presentationController,
              let containerView = presentationController.containerView,
              let sheetView = presentationController.presentedView else {
            return
        }

        let shouldUseLeadingAnchor = traitCollection.userInterfaceIdiom == .pad
            && containerView.bounds.width >= 600

        var transform = sheetView.transform
        guard shouldUseLeadingAnchor else {
            if abs(transform.tx) > 0.5 {
                transform.tx = 0
                sheetView.transform = transform
            }
            return
        }

        guard sheetView.bounds.width > 0 else { return }
        onSheetWidthChange?(sheetView.bounds.width)

        let windowLeadingInset = view.window?.safeAreaInsets.left ?? 0
        let leadingMargin = max(containerView.safeAreaInsets.left, windowLeadingInset) + 16
        let naturalLeadingEdge = sheetView.center.x - (sheetView.bounds.width / 2)
        let translationX = leadingMargin - naturalLeadingEdge

        guard abs(transform.tx - translationX) > 0.5 else { return }
        transform.tx = translationX
        sheetView.transform = transform
    }

    private var containingPresentedController: UIViewController? {
        var controller: UIViewController? = self

        while let current = controller {
            if current.presentingViewController != nil,
               current.presentationController?.presentedViewController === current {
                return current
            }
            controller = current.parent
        }

        return nil
    }
}

struct MainUIView: View {
    let searchViewModel: SearchViewModel

    @StateObject var locationManager = LocationManager()
    @StateObject private var nearbyPinMapCoordinator = NearbyPinMapCoordinator()
    @State private var isSheetPresented = true
    @State private var liveSheetHeight: CGFloat = 350
    @State private var locationOpacity: CGFloat = 1
    @State private var text = ""
    @State var tempSheetOpacity: CGFloat = 0
    @State private var nearbyPinActive = false
    @State private var nearbyPinCoordinate: CLLocationCoordinate2D?
    @State private var mapViewportSize: CGSize = .zero
    @State private var mapCameraRevision: UInt64 = 0
    @State private var searchFocusRequest = 0
    @State private var isSearchSheetTransitioning = false
    @State private var nativeSheetWidth: CGFloat = 0
    @GestureState private var legacyDrawerDragOffset: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass


    var body: some View {
        ZStack {
            baseMapView
                .catenaryOnChange(of: viewobject.camera) { _, camera in
                    guard camera.lastReasonForChange == nil
                            || camera.lastReasonForChange == .programmatic else {
                        return
                    }
                    mapCameraRevision &+= 1
                }
                .onOpenURL { url in
                    viewobject.openDeepLink(url)
                    isSheetPresented = true
                }
                .catenaryOnChange(of: viewobject.catenaryStack) { _, stack in
                    guard !stack.isEmpty else { return }
                    isSheetPresented = true
                    if viewobject.presDetent != .large {
                        viewobject.presDetent = .large
                    }
                }
                .sheet(isPresented: nativeSheetPresentationBinding) {
                    bottomDrawerSheet
                }
                .catenaryOnChange(of: viewobject.showLayerSelector) { last, current in
                    withAnimation(.catenaryBouncy) {
                        if current {
                            isSheetPresented = false
                        } else {
                            isSheetPresented = true
                        }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if usesLegacyTabletDrawer, isSheetPresented {
                        legacyTabletDrawer
                            .padding(16)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .overlay {
                    if nearbyPinActive, nearbyPinCoordinate != nil {
                        DraggableNearbyPinOverlay(
                            coordinate: $nearbyPinCoordinate,
                            mapCoordinator: nearbyPinMapCoordinator
                        )
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSheetPresented {
                        floatingToolBar()
                            .padding(.trailing, 15)
                            .padding(.bottom, usesLeadingTabletLayout ? 15 : 0)
                            .transition(.move(edge: .trailing))
                    }
                }
                .overlay(alignment: usesLeadingTabletLayout ? .topLeading : .top) {
                    if isSheetPresented,
                       viewobject.currentStackItem == nil,
                       viewobject.presDetent != .large {
                        SearchLauncher(
                            onSearch: beginSearch,
                            onSettingsClick: { viewobject.push(.settings) }
                        )
                        .frame(width: usesLeadingTabletLayout ? tabletPaneWidth : nil)
                        .padding()
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(.opacity)
                    }
                }

        }
        .catenaryOnGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { _, newSize in
            mapViewportSize = newSize
            if usesLegacyTabletDrawer, viewobject.presDetent == .large {
                liveSheetHeight = max(newSize.height - 32, 80)
            }
        }
        .task(id: searchFocusRequest) {
            guard searchFocusRequest > 0 else { return }

            try? await Task.sleep(nanoseconds: 450_000_000)
            isSearchSheetTransitioning = false
        }
        .catenaryOnChange(of: viewobject.presDetent) { _, detent in
            if detent == .large {
                if usesLegacyTabletDrawer {
                    locationOpacity = 0
                    liveSheetHeight = legacyDrawerMaximumHeight
                }
                return
            }

            isSearchSheetTransitioning = false
            locationOpacity = 1
            liveSheetHeight = detent == .height(80) ? 80 : 350
        }
        .task {
            locationManager.checkLocationAuthorization()
            useInitialUserLocationIfNeeded()
        }
        .catenaryOnChange(of: locationManager.lastKnownLocation?.latitude) { _, _ in
            useInitialUserLocationIfNeeded()
        }
        .catenaryOnChange(of: locationManager.lastKnownLocation?.longitude) { _, _ in
            useInitialUserLocationIfNeeded()
        }
    }
    @EnvironmentObject var viewobject: viewObject

    private var baseMapView: some View {
        mapLibreView(
            locationManager: locationManager,
            nearbyPinMapCoordinator: nearbyPinMapCoordinator,
            nearbyPinActive: nearbyPinActive,
            nearbyPinCoordinate: nearbyPinCoordinate,
            contentInset: mapContentInset,
            camera: $viewobject.camera,
            cameraRevision: mapCameraRevision,
            layerSettings: viewobject.allLayerSettings,
            selectedStopContext: viewobject.selectedStopContext,
            viewobject: viewobject
        )
        .equatable()
    }

    private var bottomDrawerSheet: some View {
        drawerContent(sheetHeight: liveSheetHeight)
            .presentationDetents([.height(80), .height(350), .large], selection: $viewobject.presDetent)
            .presentationBackgroundInteraction(.enabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
            .interactiveDismissDisabled()
            .background(
                NativeSheetLeadingAnchor(sheetWidth: $nativeSheetWidth)
            )
            .catenaryOnGeometryChange(for: CGFloat.self) { proxy in
                max(proxy.size.height, 0)
            } action: { _, newValue in
                guard !isSearchSheetTransitioning else { return }

                let maximumHeight = viewobject.largeDetentHeight > 0
                    ? viewobject.largeDetentHeight
                    : newValue
                let boundedHeight = min(newValue, maximumHeight)
                if abs(liveSheetHeight - boundedHeight) > 0.5 {
                    liveSheetHeight = boundedHeight
                }

                let progress = max(min((newValue - 400) / 50, 1), 0)
                let toolbarOpacity = 1 - progress
                if abs(locationOpacity - toolbarOpacity) > 0.005 {
                    locationOpacity = toolbarOpacity
                }
            }
    }

    private func drawerContent(sheetHeight: CGFloat) -> some View {
        BottomDrawer(
            selectedDetent: $viewobject.presDetent,
            sheetHeight: sheetHeight,
            locationManager: locationManager,
            searchViewModel: searchViewModel,
            focusRequest: searchFocusRequest,
            nearbyPinActive: $nearbyPinActive,
            nearbyPinCoordinate: $nearbyPinCoordinate
        )
        .ignoresSafeArea(.keyboard)
    }

    private var legacyTabletDrawer: some View {
        drawerContent(sheetHeight: legacyDrawerVisibleHeight)
            .frame(width: tabletPaneWidth, height: legacyDrawerVisibleHeight)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .top) {
                legacyDrawerDragHandle
            }
            .shadow(radius: 12, y: 4)
    }

    private var legacyDrawerDragHandle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: 36, height: 5)
            .frame(width: 96, height: 28)
            .contentShape(Rectangle())
            .gesture(legacyDrawerDragGesture)
            .accessibilityLabel(Text("Resize drawer"))
    }

    private var legacyDrawerDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .updating($legacyDrawerDragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                settleLegacyDrawer(predictedTranslation: value.predictedEndTranslation.height)
            }
    }

    private var legacyDrawerMaximumHeight: CGFloat {
        let viewportHeight = mapViewportSize.height > 0
            ? mapViewportSize.height
            : UIScreen.main.bounds.height
        return max(viewportHeight - 32, 80)
    }

    private var legacyDrawerBaseHeight: CGFloat {
        if viewobject.presDetent == .large {
            return legacyDrawerMaximumHeight
        }
        if viewobject.presDetent == .height(80) {
            return 80
        }
        return min(350, legacyDrawerMaximumHeight)
    }

    private var legacyDrawerVisibleHeight: CGFloat {
        min(
            max(legacyDrawerBaseHeight - legacyDrawerDragOffset, 80),
            legacyDrawerMaximumHeight
        )
    }

    private func settleLegacyDrawer(predictedTranslation: CGFloat) {
        let threshold: CGFloat = 44
        guard abs(predictedTranslation) >= threshold else { return }

        let nextDetent: PresentationDetent
        if predictedTranslation < 0 {
            nextDetent = viewobject.presDetent == .height(80) ? .height(350) : .large
        } else {
            nextDetent = viewobject.presDetent == .large ? .height(350) : .height(80)
        }

        withAnimation(.catenaryBouncy) {
            viewobject.presDetent = nextDetent
        }
    }

    private func beginSearch() {
        guard viewobject.currentStackItem == nil else { return }
        isSearchSheetTransitioning = true
        locationOpacity = 0
        viewobject.presDetent = .large
        searchFocusRequest &+= 1
    }

    private func useInitialUserLocationIfNeeded() {
        guard let coordinate = locationManager.lastKnownLocation else { return }
        viewobject.useInitialUserLocationIfNeeded(coordinate)
    }

    private var nativeSheetPresentationBinding: Binding<Bool> {
        Binding(
            get: {
                isSheetPresented && !usesLegacyTabletDrawer
            },
            set: { presented in
                guard !usesLegacyTabletDrawer else { return }
                isSheetPresented = presented
            }
        )
    }

    private var usesLegacyTabletDrawer: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              horizontalSizeClass == .regular else {
            return false
        }

        if #available(iOS 17.0, *) {
            return false
        }
        return true
    }

    private var usesTabletLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && mapViewportSize.width >= 600
    }

    private var usesLeadingTabletLayout: Bool {
        usesLegacyTabletDrawer || usesTabletLayout
    }

    private var tabletPaneWidth: CGFloat {
        let viewportWidth = mapViewportSize.width > 0
            ? mapViewportSize.width
            : UIScreen.main.bounds.width
        let availableWidth = max(viewportWidth - 32, 0)
        let fallbackWidth = min(600, max(viewportWidth * 0.5, 320))
        let preferredWidth = nativeSheetWidth > 0 ? nativeSheetWidth : fallbackWidth
        return min(preferredWidth, availableWidth)
    }

    private var mapContentInset: UIEdgeInsets {
        guard isSheetPresented, mapViewportSize.height > 0 else { return .zero }
        guard viewobject.presDetent == .large else { return .zero }

        if usesLeadingTabletLayout {
            return UIEdgeInsets(
                top: 0,
                left: tabletPaneWidth + 16,
                bottom: 0,
                right: 0
            )
        }

        return UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: mapViewportSize.height / 2,
            right: 0
        )
    }

    @ViewBuilder
    func floatingToolBar() -> some View {
        Group {
            VStack {
                if viewobject.currentRotation != 0 {
                    Button {
                        //                locationManager.checkLocationAuthorization()
                        viewobject.camera.setDirection(0)
                    } label: {
                        Image(systemName: "location.north.line")
                            .rotationEffect(Angle(degrees: viewobject.currentRotation))
                            .padding()
                            .background(.regularMaterial, in: Circle())
                    }
                    .transition(.opacity.combined(with: .scale))
                    .foregroundStyle(Color.primary)
                }
                VStack {

                    Button {
                        //                locationManager.checkLocationAuthorization()
                        //                    viewobject.camera.setDirection(0)
                        viewobject.showLayerSelector.toggle()
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                    }
                    .padding(.bottom)
                    Button {
                        locationManager.checkLocationAuthorization()
                        viewobject.camera = .trackUserLocation(zoom: 15)
                    } label: {
                        Image(systemName: "location\(viewobject.centered ? ".fill" : "")")
                    }
                    .padding(.top)

                }
                .padding(.all, 10)
                .background(.regularMaterial, in: Capsule())

            }
            .font(.title3)
            .offset(y: usesLeadingTabletLayout ? 0 : -min(liveSheetHeight, 350))
            .opacity(locationOpacity)
        }

    }


}




#Preview {
    MainUIView(searchViewModel: SearchViewModel()).environmentObject(viewObject())
}

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

private struct MainViewGeometry: Equatable {
    let size: CGSize
    let topSafeAreaInset: CGFloat
    let bottomSafeAreaInset: CGFloat
}

struct MainUIView: View {
    let searchViewModel: SearchViewModel

    @StateObject var locationManager = LocationManager()
    @StateObject private var nearbyPinMapCoordinator = NearbyPinMapCoordinator()
    @State private var isSheetPresented = true
    @State private var liveSheetHeight: CGFloat = 350
    @State private var collapsedNativeSheetHeight: CGFloat?
    @State private var locationOpacity: CGFloat = 1
    @State private var text = ""
    @State var tempSheetOpacity: CGFloat = 0
    @State private var nearbyPinActive = false
    @State private var nearbyPinCoordinate: CLLocationCoordinate2D?
    @State private var mapViewportSize: CGSize = .zero
    @State private var mapTopSafeAreaInset: CGFloat = 0
    @State private var mapBottomSafeAreaInset: CGFloat = 0
    @State private var floatingToolbarHeight: CGFloat = 0
    @State private var mapCameraRevision: UInt64 = 0
    @State private var searchFocusRequest = 0
    @State private var isSearchSheetTransitioning = false
    @State private var nativeSheetWidth: CGFloat = 0
    @State private var drawerDragOffset: CGFloat = 0
    @State private var isLandscapeSearchRequested = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass


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
                    isLandscapeSearchRequested = false
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
                    if usesCustomDrawer, isSheetPresented {
                        leadingDrawer
                            .padding(.horizontal, drawerOuterPadding)
                            .padding(.top, drawerOuterPadding)
                            .padding(.bottom, drawerBottomPadding)
                            .ignoresSafeArea(
                                .container,
                                edges: usesLandscapePhoneDrawer ? .bottom : []
                            )
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
                            .catenaryOnGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { _, newHeight in
                                floatingToolbarHeight = newHeight
                            }
                            .padding(.trailing, 15)
                            .padding(.bottom, floatingToolbarBottomPadding)
                            .transition(.move(edge: .trailing))
                    }
                }
                .overlay(alignment: usesLeadingPaneLayout ? .topLeading : .top) {
                    if isSheetPresented,
                       viewobject.currentStackItem == nil,
                       viewobject.presDetent != .large {
                        SearchLauncher(
                            onSearch: beginSearch,
                            onSettingsClick: { viewobject.push(.settings) }
                        )
                        .frame(width: usesLeadingPaneLayout ? leadingPaneWidth : nil)
                        .padding(drawerOuterPadding)
                        .offset(y: landscapeSearchLauncherYOffset)
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

        }
        .catenaryOnGeometryChange(for: MainViewGeometry.self) { proxy in
            MainViewGeometry(
                size: proxy.size,
                topSafeAreaInset: proxy.safeAreaInsets.top,
                bottomSafeAreaInset: proxy.safeAreaInsets.bottom
            )
        } action: { _, geometry in
            mapViewportSize = geometry.size
            mapTopSafeAreaInset = geometry.topSafeAreaInset
            mapBottomSafeAreaInset = geometry.bottomSafeAreaInset

            // A medium-height drawer is not useful on a short landscape phone.
            // Preserve roughly the same amount of visible content by promoting
            // the portrait medium detent to the expanded side drawer.
            if usesLandscapePhoneDrawer, viewobject.presDetent == .height(350) {
                viewobject.presDetent = .large
            }

            if usesCustomDrawer, viewobject.presDetent == .large {
                liveSheetHeight = drawerMaximumHeight
                locationOpacity = usesLandscapePhoneDrawer ? 1 : 0
            }
        }
        .task(id: searchFocusRequest) {
            guard searchFocusRequest > 0 else { return }

            try? await Task.sleep(nanoseconds: 450_000_000)
            isSearchSheetTransitioning = false
        }
        .catenaryOnChange(of: viewobject.presDetent) { _, detent in
            if usesLandscapePhoneDrawer, detent == .height(350) {
                viewobject.presDetent = .large
                return
            }

            if detent == .large {
                if usesCustomDrawer {
                    locationOpacity = usesLandscapePhoneDrawer ? 1 : 0
                    liveSheetHeight = drawerMaximumHeight
                } else if usesPortraitPhoneDrawer {
                    withAnimation(.easeOut(duration: 0.18)) {
                        locationOpacity = 0
                    }
                }
                return
            }

            isSearchSheetTransitioning = false
            if usesLandscapePhoneDrawer {
                isLandscapeSearchRequested = false
            }
            if usesPortraitPhoneDrawer {
                withAnimation(.easeOut(duration: 0.18)) {
                    locationOpacity = 1
                }
            } else {
                locationOpacity = 1
            }
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
            .presentationDragIndicator(.visible)
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

                // A fixed detent's SwiftUI geometry can include safe-area/presentation
                // chrome, so the measured closed height is not guaranteed to be 80.
                // While the selection still says "collapsed", retain the smallest
                // geometry value we observe. During an upward drag the height grows,
                // leaving this as a stable baseline for the compact-pill crossfade.
                if viewobject.presDetent == .height(80) {
                    if let collapsedNativeSheetHeight {
                        self.collapsedNativeSheetHeight = min(
                            collapsedNativeSheetHeight,
                            boundedHeight
                        )
                    } else {
                        collapsedNativeSheetHeight = boundedHeight
                    }
                }

                if abs(liveSheetHeight - boundedHeight) > 0.5 {
                    liveSheetHeight = boundedHeight
                }

                // Match Android's anchored FAB behavior on portrait phones: keep
                // the toolbar visible while the sheet is moving and hide it only
                // after the sheet settles at the expanded detent.
                if !usesPortraitPhoneDrawer {
                    let progress = max(min((newValue - 400) / 50, 1), 0)
                    let toolbarOpacity = 1 - progress
                    if abs(locationOpacity - toolbarOpacity) > 0.005 {
                        locationOpacity = toolbarOpacity
                    }
                }
            }
    }

    private func drawerContent(sheetHeight: CGFloat) -> some View {
        BottomDrawer(
            selectedDetent: $viewobject.presDetent,
            sheetHeight: sheetHeight,
            collapsedDrawerHeight: usesCustomDrawer ? 80 : collapsedNativeSheetHeight,
            locationManager: locationManager,
            searchViewModel: searchViewModel,
            focusRequest: searchFocusRequest,
            showsSearchBarWhenInactive: !usesLandscapePhoneDrawer || isLandscapeSearchRequested,
            nearbyPinActive: $nearbyPinActive,
            nearbyPinCoordinate: $nearbyPinCoordinate
        )
        .ignoresSafeArea(.keyboard)
    }

    private var leadingDrawer: some View {
        drawerContent(sheetHeight: drawerVisibleHeight)
            .frame(width: leadingPaneWidth, height: drawerVisibleHeight)
            .background(drawerMaterial)
            .clipShape(RoundedRectangle(cornerRadius: drawerCornerRadius, style: .continuous))
            .overlay(alignment: .top) {
                drawerDragHandle
            }
            .shadow(radius: 12, y: 4)
    }

    private var drawerDragHandle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: 36, height: 5)
            .frame(width: 112, height: usesLandscapePhoneDrawer ? 44 : 28)
            .contentShape(Rectangle())
            .gesture(drawerDragGesture)
            .accessibilityLabel(Text("Resize drawer"))
    }

    private var isLandscapeDrawerCollapsed: Bool {
        usesLandscapePhoneDrawer && viewobject.presDetent == .height(80)
    }

    private var drawerMaterial: Material {
        isLandscapeDrawerCollapsed ? .thinMaterial : .regularMaterial
    }

    private var drawerCornerRadius: CGFloat {
        isLandscapeDrawerCollapsed ? 40 : 18
    }

    private var drawerDragGesture: some Gesture {
        // The handle moves while drawerVisibleHeight changes. Measuring in the
        // root coordinate space prevents that relayout from feeding back into
        // the gesture's reported translation and making the drawer jitter.
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                drawerDragOffset = value.translation.height
            }
            .onEnded { value in
                settleDrawer(
                    translation: value.translation.height,
                    predictedTranslation: value.predictedEndTranslation.height
                )
            }
    }

    private var drawerMaximumHeight: CGFloat {
        let viewportHeight = mapViewportSize.height > 0
            ? mapViewportSize.height
            : UIScreen.main.bounds.height
        let bottomPadding = usesLandscapePhoneDrawer ? 0 : drawerOuterPadding
        let availableHeight = viewportHeight - drawerOuterPadding - bottomPadding
        return max(availableHeight, 80)
    }

    private var drawerBaseHeight: CGFloat {
        if viewobject.presDetent == .height(80) {
            return 80
        }

        // Landscape phones intentionally expose only collapsed and expanded.
        // Treat any stale/programmatic medium detent as expanded.
        if usesLandscapePhoneDrawer {
            return drawerMaximumHeight
        }

        if viewobject.presDetent == .large {
            return drawerMaximumHeight
        }
        return min(350, drawerMaximumHeight)
    }

    private var drawerVisibleHeight: CGFloat {
        min(
            max(drawerBaseHeight - drawerDragOffset, 80),
            drawerMaximumHeight
        )
    }

    private func settleDrawer(translation: CGFloat, predictedTranslation: CGFloat) {
        let effectiveTranslation: CGFloat
        let threshold: CGFloat
        if usesLandscapePhoneDrawer {
            // Slow, deliberate drags should count in landscape; relying only on
            // release velocity made the collapsed drawer very difficult to open.
            effectiveTranslation = translation
            threshold = 20
        } else {
            effectiveTranslation = predictedTranslation
            threshold = 44
        }

        let nextDetent: PresentationDetent
        if abs(effectiveTranslation) < threshold {
            nextDetent = viewobject.presDetent
        } else if usesLandscapePhoneDrawer {
            nextDetent = effectiveTranslation < 0 ? .large : .height(80)
        } else if effectiveTranslation < 0 {
            nextDetent = viewobject.presDetent == .height(80) ? .height(350) : .large
        } else {
            nextDetent = viewobject.presDetent == .large ? .height(350) : .height(80)
        }

        withAnimation(.catenaryBouncy) {
            viewobject.presDetent = nextDetent
            drawerDragOffset = 0
        }
    }

    private func beginSearch() {
        guard viewobject.currentStackItem == nil else { return }
        isSearchSheetTransitioning = true
        isLandscapeSearchRequested = usesLandscapePhoneDrawer
        locationOpacity = usesLandscapePhoneDrawer ? 1 : 0
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
                isSheetPresented && !usesCustomDrawer
            },
            set: { presented in
                guard !usesCustomDrawer else { return }
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

    private var usesLandscapePhoneDrawer: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }

        if mapViewportSize.width > 0, mapViewportSize.height > 0 {
            return mapViewportSize.width > mapViewportSize.height
        }
        return verticalSizeClass == .compact
    }

    private var usesCustomDrawer: Bool {
        usesLegacyTabletDrawer || usesLandscapePhoneDrawer
    }

    private var usesPortraitPhoneDrawer: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && !usesLandscapePhoneDrawer
    }

    private var usesTabletLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && mapViewportSize.width >= 600
    }

    private var usesLeadingPaneLayout: Bool {
        usesCustomDrawer || usesTabletLayout
    }

    private var floatingToolbarBottomPadding: CGFloat {
        if usesPortraitPhoneDrawer { return 8 }
        return usesLeadingPaneLayout ? 15 : 0
    }

    private var floatingToolbarYOffset: CGFloat {
        if usesPortraitPhoneDrawer {
            // A fixed-height native sheet includes the home-indicator inset,
            // while a bottom-aligned overlay starts above that inset. Remove it
            // here so the explicit padding is the actual gap above the drawer.
            return -max(liveSheetHeight - mapBottomSafeAreaInset, 0)
        }
        return usesLeadingPaneLayout ? 0 : -min(liveSheetHeight, 350)
    }

    private var floatingToolbarOpacity: CGFloat {
        guard usesPortraitPhoneDrawer,
              mapViewportSize.height > 0,
              floatingToolbarHeight > 0 else {
            return locationOpacity
        }

        let toolbarTop = mapViewportSize.height
            - liveSheetHeight
            - floatingToolbarBottomPadding
            - floatingToolbarHeight
        let fadeDistance: CGFloat = 44
        let clearanceOpacity = min(
            max((toolbarTop - mapTopSafeAreaInset) / fadeDistance, 0),
            1
        )
        return locationOpacity * clearanceOpacity
    }

    private var drawerOuterPadding: CGFloat {
        usesLandscapePhoneDrawer ? 8 : 16
    }

    private var landscapeSearchLauncherYOffset: CGFloat {
        guard usesLandscapePhoneDrawer else { return 0 }
        return min(drawerDragOffset, 0)
    }

    private var drawerBottomPadding: CGFloat {
        guard usesLandscapePhoneDrawer else { return drawerOuterPadding }

        let heightRange = max(drawerMaximumHeight - 80, 1)
        let expansionProgress = min(
            max((drawerVisibleHeight - 80) / heightRange, 0),
            1
        )
        return drawerOuterPadding * (1 - expansionProgress)
    }

    private var leadingPaneWidth: CGFloat {
        if usesLandscapePhoneDrawer {
            return landscapePhoneDrawerWidth
        }
        if usesLegacyTabletDrawer {
            return min(tabletPaneWidth, 440)
        }
        return tabletPaneWidth
    }

    private var landscapePhoneDrawerWidth: CGFloat {
        let viewportWidth = mapViewportSize.width > 0
            ? mapViewportSize.width
            : UIScreen.main.bounds.width

        // The left padding plus the panel width ends at the screen midpoint.
        return max((viewportWidth / 2) - drawerOuterPadding, 0)
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

        if usesLeadingPaneLayout {
            return UIEdgeInsets(
                top: 0,
                left: leadingPaneWidth + drawerOuterPadding,
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
            .offset(y: floatingToolbarYOffset)
            // The native sheet already reports intermediate heights. Avoid adding
            // another animation layer so the toolbar stays locked to its top edge.
            .animation(nil, value: liveSheetHeight)
            .opacity(floatingToolbarOpacity)
            .allowsHitTesting(floatingToolbarOpacity > 0.01)
            .accessibilityHidden(floatingToolbarOpacity <= 0.01)
        }

    }


}




#Preview {
    MainUIView(searchViewModel: SearchViewModel()).environmentObject(viewObject())
}

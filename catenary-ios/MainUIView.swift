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
    @Binding var sheetHeight: CGFloat

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

        let heightBinding = $sheetHeight
        controller.onSheetHeightChange = { height in
            guard abs(heightBinding.wrappedValue - height) > 0.5 else { return }
            heightBinding.wrappedValue = height
        }
    }
}

private final class NativeSheetLeadingAnchorController: UIViewController {
    var onSheetWidthChange: ((CGFloat) -> Void)?
    var onSheetHeightChange: ((CGFloat) -> Void)?
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

        // Read straight from the presentation controller's own view, which UIKit
        // moves directly under the user's finger during an interactive drag.
        // viewDidLayoutSubviews fires on every one of those layout passes, so this
        // tracks the true on-screen sheet edge with far less lag than waiting for
        // SwiftUI to re-run its own layout and report back through a GeometryReader.
        if sheetView.bounds.height > 0 {
            onSheetHeightChange?(sheetView.bounds.height)
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
    @State private var pendingCollapsedNativeSheetHeight: CGFloat?
    @State private var nativeSheetChromeBias: CGFloat?
    @State private var pendingNativeSheetChromeBias: CGFloat?
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
    @State private var nativeSheetLiveHeight: CGFloat = 0
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
                    if isSheetPresented, !usesPortraitPhoneDrawer {
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
            // Native sheets include presentation/safe-area chrome in their measured
            // height. Keep that geometry as the source of truth so the FAB stays a
            // fixed distance above the drawer instead of jumping at detent settle.
            if usesCustomDrawer {
                liveSheetHeight = detent == .height(80) ? 80 : 350
            } else if usesPortraitPhoneDrawer,
                      let semanticHeight = semanticSheetHeight(for: detent) {
                // Apply the already-calibrated chrome bias immediately instead of
                // waiting for the next native-sheet geometry sample. Without this,
                // liveSheetHeight stays at the previous detent's height for a beat
                // after expanding, so the FAB renders too low and ends up behind
                // the sheet until the async measurement catches up.
                //
                // Only jump ahead of the measurement when it makes the sheet
                // look taller. Doing this on a collapse assumes the sheet has
                // already visually shrunk to match the new detent, which isn't
                // guaranteed (e.g. rapid detent toggling can desync the two) and
                // would sink the FAB behind a sheet that's actually still tall.
                let estimate = semanticHeight + (nativeSheetChromeBias ?? 0)
                if estimate > liveSheetHeight {
                    liveSheetHeight = estimate
                }
            }
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
            .background {
                if usesPortraitPhoneDrawer {
                    NativeSheetFloatingToolbarHost {
                        floatingToolBar(attachedToPortraitSheet: true)
                    }
                }
            }
            .background(
                NativeSheetLeadingAnchor(sheetWidth: $nativeSheetWidth, sheetHeight: $nativeSheetLiveHeight)
            )
            .catenaryOnGeometryChange(for: CGFloat.self) { proxy in
                max(proxy.size.height, 0)
            } action: { _, newValue in
                // nativeSheetLiveHeight (below) owns portrait phones: it reads
                // straight from the presentation controller's own view, so it
                // tracks the true on-screen edge with far less lag than this
                // content geometry read, which only reports after our own
                // content re-lays-out in response to the sheet resizing it.
                // Letting both paths feed the same calibration state for the
                // same device class made two independently-timed measurements
                // fight over the same "did the last two samples agree" check,
                // so each owns a disjoint set of devices instead.
                guard !usesPortraitPhoneDrawer else { return }
                applyMeasuredSheetHeight(newValue, cappedToLargeDetent: true)
            }
            .catenaryOnChange(of: nativeSheetLiveHeight) { _, newValue in
                guard usesPortraitPhoneDrawer else { return }
                applyMeasuredSheetHeight(newValue, cappedToLargeDetent: false)
            }
    }

    private func applyMeasuredSheetHeight(_ measuredHeight: CGFloat, cappedToLargeDetent: Bool) {
        guard !isSearchSheetTransitioning else { return }

        let boundedHeight: CGFloat
        if cappedToLargeDetent {
            let maximumHeight = viewobject.largeDetentHeight > 0
                ? viewobject.largeDetentHeight
                : measuredHeight
            boundedHeight = min(measuredHeight, maximumHeight)
        } else {
            // nativeSheetLiveHeight is read directly from the real, on-screen
            // presented view, so it's already bounded by the actual screen —
            // no need for the largeDetentHeight cap used for the SwiftUI
            // content-geometry path.
            boundedHeight = measuredHeight
        }

        // A fixed detent's SwiftUI geometry can include safe-area/presentation
        // chrome, so the measured closed height is not guaranteed to be 80.
        // While the selection still says "collapsed", retain the smallest
        // geometry value we observe. During an upward drag the height grows,
        // leaving this as a stable baseline for the compact-pill crossfade.
        //
        // presDetent tracks an interactive drag live, so it can briefly read
        // .height(80) while merely passing through that zone mid-gesture
        // (e.g. dragging the sheet down and back up). A single in-flight
        // sample from that pass-through can be spuriously low and would
        // otherwise get latched in forever via min(). Require the same
        // reading on two consecutive frames before trusting it as settled.
        if viewobject.presDetent == .height(80),
           boundedHeight >= 80 {
            if let pendingCollapsedNativeSheetHeight,
               abs(pendingCollapsedNativeSheetHeight - boundedHeight) < 0.5 {
                if let collapsedNativeSheetHeight {
                    self.collapsedNativeSheetHeight = min(
                        collapsedNativeSheetHeight,
                        boundedHeight
                    )
                } else {
                    collapsedNativeSheetHeight = boundedHeight
                }
            } else {
                pendingCollapsedNativeSheetHeight = boundedHeight
            }
        } else {
            pendingCollapsedNativeSheetHeight = nil
        }

        // Generalized chrome-bias calibration for the FAB's positioning math,
        // sampled from whichever fixed detent (.height(80) or .height(350))
        // we're currently settled at rather than only the collapsed one. The
        // app's default launch detent is .height(350), so relying solely on
        // .height(80) left the FAB using an uncalibrated (too-large) gap
        // until the user happened to collapse the sheet at least once. Same
        // two-frame stability requirement to reject mid-drag pass-through.
        if usesPortraitPhoneDrawer,
           let semanticHeight = semanticSheetHeight(for: viewobject.presDetent),
           boundedHeight >= semanticHeight {
            let candidateBias = boundedHeight - semanticHeight
            if let pendingNativeSheetChromeBias,
               abs(pendingNativeSheetChromeBias - candidateBias) < 0.5 {
                if let nativeSheetChromeBias {
                    self.nativeSheetChromeBias = min(nativeSheetChromeBias, candidateBias)
                } else {
                    nativeSheetChromeBias = candidateBias
                }
            } else {
                pendingNativeSheetChromeBias = candidateBias
            }
        } else {
            pendingNativeSheetChromeBias = nil
        }

        if abs(liveSheetHeight - boundedHeight) > 0.5 {
            liveSheetHeight = boundedHeight
        }

        // Match Android's anchored FAB behavior on portrait phones: keep
        // the toolbar visible while the sheet is moving and hide it only
        // after the sheet settles at the expanded detent.
        if !usesPortraitPhoneDrawer {
            let progress = max(min((measuredHeight - 400) / 50, 1), 0)
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

    private var drawerMidwayHeight: CGFloat {
        guard usesTabletDrawer else {
            return min(350, drawerMaximumHeight)
        }

        let viewportHeight = mapViewportSize.height > 0
            ? mapViewportSize.height
            : UIScreen.main.bounds.height

        // Android wide layout places the midway anchor at half the screen.
        return min(max(viewportHeight / 2, 80), drawerMaximumHeight)
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
        return drawerMidwayHeight
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

    private var usesTabletDrawer: Bool {
        // Tablets always use the custom bottom-leading drawer. This avoids the
        // centered native iPad sheet and matches Android's wide layout.
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var usesLandscapePhoneDrawer: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }

        if mapViewportSize.width > 0, mapViewportSize.height > 0 {
            return mapViewportSize.width > mapViewportSize.height
        }
        return verticalSizeClass == .compact
    }

    private var usesCustomDrawer: Bool {
        usesTabletDrawer || usesLandscapePhoneDrawer
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

    /// The known logical height for a fixed detent, or nil for `.large` (which
    /// varies with the viewport and isn't used for this positioning math since
    /// the FAB is faded out entirely at `.large` on portrait phones).
    private func semanticSheetHeight(for detent: PresentationDetent) -> CGFloat? {
        if detent == .height(80) { return 80 }
        if detent == .height(350) { return 350 }
        return nil
    }

    private var effectivePortraitSheetHeight: CGFloat {
        guard usesPortraitPhoneDrawer else { return liveSheetHeight }

        // SwiftUI's native-sheet geometry can contain a device-dependent constant
        // amount of safe-area/presentation chrome. Until that bias has been
        // calibrated from an observed sample, trust the semantic detent height
        // (when resolvable) instead of raw, chrome-inflated geometry — otherwise
        // a cold launch (which starts at .height(350), not .height(80)) would
        // flash an oversized gap before the first sample ever arrives.
        guard let nativeSheetChromeBias else {
            return semanticSheetHeight(for: viewobject.presDetent) ?? liveSheetHeight
        }

        return max(liveSheetHeight - nativeSheetChromeBias, 80)
    }

    private var floatingToolbarBottomPadding: CGFloat {
        if usesPortraitPhoneDrawer { return 8 }
        return usesLeadingPaneLayout ? 15 : 0
    }

    private var floatingToolbarYOffset: CGFloat {
        if usesPortraitPhoneDrawer {
            // Use the calibrated logical drawer height rather than raw
            // native-sheet geometry, which can include presentation chrome.
            return -effectivePortraitSheetHeight
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
            - effectivePortraitSheetHeight
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
        if usesTabletDrawer {
            return tabletPaneWidth
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

        // Match Android's wide layout: the drawer occupies the leading half
        // of the viewport, accounting for the outer leading margin.
        return max((viewportWidth / 2) - drawerOuterPadding, 0)
    }

    private var mapContentInset: UIEdgeInsets {
        guard isSheetPresented, mapViewportSize.height > 0 else { return .zero }

        if usesLeadingPaneLayout {
            // Android shifts the map into the unobscured half at both the
            // midway and expanded wide-layout snap points.
            guard viewobject.presDetent != .height(80) else { return .zero }
            return UIEdgeInsets(
                top: 0,
                left: leadingPaneWidth + drawerOuterPadding,
                bottom: 0,
                right: 0
            )
        }

        guard viewobject.presDetent == .large else { return .zero }

        return UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: mapViewportSize.height / 2,
            right: 0
        )
    }

    @ViewBuilder
    func floatingToolBar(attachedToPortraitSheet: Bool = false) -> some View {
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
            .offset(y: attachedToPortraitSheet ? 0 : floatingToolbarYOffset)
            // The native sheet already reports intermediate heights. Avoid adding
            // another animation layer so the toolbar stays locked to its top edge.
            .animation(nil, value: liveSheetHeight)
            .animation(attachedToPortraitSheet ? .easeOut(duration: 0.18) : nil, value: locationOpacity)
            .opacity(attachedToPortraitSheet ? locationOpacity : floatingToolbarOpacity)
            .allowsHitTesting((attachedToPortraitSheet ? locationOpacity : floatingToolbarOpacity) > 0.01)
            .accessibilityHidden((attachedToPortraitSheet ? locationOpacity : floatingToolbarOpacity) <= 0.01)
        }

    }


}




#Preview {
    MainUIView(searchViewModel: SearchViewModel()).environmentObject(viewObject())
}

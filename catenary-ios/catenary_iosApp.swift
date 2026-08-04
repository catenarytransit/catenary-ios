//
//  catenary_iosApp.swift
//  catenary-ios
//
//

import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI


var GlobalViewObject: viewObject = viewObject()

@main
struct CatenaryMapsApp: App {
    @StateObject var viewobject = GlobalViewObject
    @StateObject private var searchViewModel = SearchViewModel()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
        
    var body: some Scene {
        WindowGroup {
            MainUIView(searchViewModel: searchViewModel)
                .environmentObject(viewobject)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions:
                   [UIApplication.LaunchOptionsKey : Any]? = nil)
  -> Bool { return true }
 
  func application(_ application: UIApplication,
                   configurationForConnecting connectingSceneSession: UISceneSession,
                  options: UIScene.ConnectionOptions) -> UISceneConfiguration {
      let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
      if connectingSceneSession.role == .windowApplication {
          configuration.delegateClass = SceneDelegate.self
      }
      return configuration
  }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    var secondaryWindow: UIWindow?
    private var measurementWindow: UIWindow?   // third hidden window

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {

        guard let windowScene = scene as? UIWindowScene else { return }

        setupSecondaryOverlayWindow(in: windowScene)

        DispatchQueue.main.async {
            self.measureLargeDetentHeightSilently(in: windowScene)
        }
    }

    func setupSecondaryOverlayWindow(in scene: UIWindowScene) {
        let secondaryViewController = UIHostingController(
            rootView: OverlayRoot().environmentObject(GlobalViewObject)
        )
        secondaryViewController.view.backgroundColor = .clear
        let secondaryWindow = PassThroughWindow(windowScene: scene)
        secondaryWindow.rootViewController = secondaryViewController
        secondaryWindow.isHidden = false
        self.secondaryWindow = secondaryWindow
    }

    private func measureLargeDetentHeightSilently(in windowScene: UIWindowScene) {
        
        let measurementWindow = UIWindow(windowScene: windowScene)
        measurementWindow.windowLevel = .normal - 1000
        measurementWindow.isHidden = false
        measurementWindow.backgroundColor = .clear
        self.measurementWindow = measurementWindow

        let rootSwiftUIView = HiddenSheetHeightMeasurer { measuredHeight in
            GlobalViewObject.largeDetentHeight = measuredHeight

            measurementWindow.isHidden = true
            self.measurementWindow = nil
        }

        let hostingController = UIHostingController(rootView: rootSwiftUIView)
        hostingController.view.backgroundColor = .clear
        measurementWindow.rootViewController = hostingController
        measurementWindow.makeKeyAndVisible()
    }
}


struct OverlayRoot: View {
    @EnvironmentObject var viewobject: viewObject
    @Environment(\.dismiss) private var dismiss
    @State var currentPage = "Rail"
//    var bigSheet: Bool {
//        withAnimation {
//            (viewobject.allLayerSettings[currentPage]?.visiblerealtimedots ?? true)
//        }
//    }
//    @State var expanded: Bool = false
    var body: some View {
        EmptyView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $viewobject.showLayerSelector) {
                
                NavigationStack {
                    LayerSelectorSheet(tabPage: $currentPage)
                        .presentationDetents([.height(380)])
                        .presentationBackgroundInteraction(PresentationBackgroundInteraction.disabled)
                        
                        .interactiveDismissDisabled(false)
                        .navigationTitle("Layers")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    viewobject.showLayerSelector = false
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                        
                    
                        
                }
                
            }
            
        
        
        //            .navigationTitle("Layers")
    }
}

struct layerSettingButton: View {
    @Binding var specificLayerSetting: Bool
    var imageName: String
    var label: LocalizedStringKey
    var sfsymbol: Bool = false
    
    var body: some View {
        VStack {
            Button {
//                withAnimation(nil) {
                    specificLayerSetting.toggle()
//                }
            } label: {
                
                (sfsymbol ? Image(systemName: imageName) : Image(imageName).resizable())
                    
                    
                    .if(sfsymbol) { $0.padding() }
                    .foregroundStyle(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.thinMaterial)
                            
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                specificLayerSetting ? Color.primary.opacity(0.65) : .clear,
                                lineWidth: 2
                            )
                    )
                    .animation(nil, value: specificLayerSetting)
                    .aspectRatio(1, contentMode: .fit)

            }
            
            if !sfsymbol {
                Text(label)
                    .lineLimit(1, reservesSpace: true)
            }
//                .if(sfsymbol) {
//                    $0.fontWidth(.compressed)
//                }
                
//                .minimumScaleFactor(0.3)
        }
    }
}

struct vehicleLabelSettingButton: View {
    @Binding var specificLayerSetting: Bool
    var imageName: String
    var label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 4) {
            Button {
                specificLayerSetting.toggle()
            } label: {
                Image(systemName: imageName)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(Color.primary)
                    .background(
                        Circle()
                            .fill(
                                specificLayerSetting
                                    ? Color.primary.opacity(0.14)
                                    : Color(uiColor: .secondarySystemBackground)
                            )
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color.primary.opacity(specificLayerSetting ? 0.55 : 0.12),
                                lineWidth: specificLayerSetting ? 1.5 : 1
                            )
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(specificLayerSetting ? .isSelected : [])

            Text(label)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}

extension View {
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        Group {
            if condition {
                AnyView(transform(self))
            } else {
                AnyView(self)
            }
        }
    }
}



struct layerTabView: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @Binding var layerSettings: LayerCategorySettings

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                layerSettingButton(specificLayerSetting: $layerSettings.shapes,
                                   imageName: "routesicon", label: "Routes")
                layerSettingButton(specificLayerSetting: $layerSettings.labelshapes,
                                   imageName: "labelsicon", label: "Labels")
                layerSettingButton(specificLayerSetting: $layerSettings.stops,
                                   imageName: "stopsicon", label: "Stops")
                layerSettingButton(specificLayerSetting: $layerSettings.labelstops,
                                   imageName: "\(colorScheme == .dark ? "dark" : "light")-stop-name",
                                   label: "Names")
                layerSettingButton(specificLayerSetting: $layerSettings.visiblerealtimedots,
                                   imageName: "vehiclesicon", label: "Vehicles")
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {

                Text("Vehicle labels")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(alignment: .top, spacing: 6) {
                    vehicleLabelSettingButton(
                        specificLayerSetting: $layerSettings.labelrealtimedots.route,
                        imageName: "point.topleft.down.curvedto.point.bottomright.up",
                        label: "Route"
                    )
                    vehicleLabelSettingButton(
                        specificLayerSetting: $layerSettings.labelrealtimedots.trip,
                        imageName: "arrow.triangle.branch",
                        label: "Trip"
                    )
                    vehicleLabelSettingButton(
                        specificLayerSetting: $layerSettings.labelrealtimedots.vehicle,
                        imageName: "tram.fill",
                        label: "Vehicle"
                    )
                    vehicleLabelSettingButton(
                        specificLayerSetting: $layerSettings.labelrealtimedots.headsign,
                        imageName: "flag.checkered",
                        label: "Headsign"
                    )
                    vehicleLabelSettingButton(
                        specificLayerSetting: $layerSettings.labelrealtimedots.speed,
                        imageName: "speedometer",
                        label: "Speed"
                    )
                    vehicleLabelSettingButton(
                        specificLayerSetting: $layerSettings.labelrealtimedots.occupancy,
                        imageName: "person.2.fill",
                        label: "Occupancy"
                    )
                    vehicleLabelSettingButton(
                        specificLayerSetting: $layerSettings.labelrealtimedots.delay,
                        imageName: "stopwatch.fill",
                        label: "Delay"
                    )
                }
                .frame(maxWidth: .infinity)

                Button {
                    layerSettings.labeltrajectories.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: layerSettings.labeltrajectories
                              ? "checkmark.square.fill"
                              : "square")
                            .font(.title3)
                        Text("Label interpolated trajectories")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(layerSettings.labeltrajectories ? .isSelected : [])
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 6)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct LayerSelectorSheet: View {
    
    @EnvironmentObject var viewobject: viewObject
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @Binding var tabPage: String
    
    var body: some View {
        tabs
            .ignoresSafeArea(edges: .bottom)
            .symbolRenderingMode(.monochrome)
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            modernTabs
        } else {
            legacyTabs
        }
    }

    @available(iOS 18.0, *)
    private var modernTabs: some View {
        TabView(selection: $tabPage) {
            Tab("Rail", systemImage: "tram.fill.tunnel", value: "Rail") {
                layerTabView(layerSettings: $viewobject.allLayerSettings.intercityrail)
            }
            Tab("Metro/Tram", systemImage: "lightrail.fill", value: "Metro/Tram") {
                layerTabView(layerSettings: $viewobject.allLayerSettings.localrail)
            }
            Tab("Bus", systemImage: "bus.fill", value: "Bus") {
                layerTabView(layerSettings: $viewobject.allLayerSettings.bus)
            }
            Tab("Other", systemImage: "ferry.fill", value: "Other") {
                layerTabView(layerSettings: $viewobject.allLayerSettings.other)
            }
//            Tab("More", systemImage: "ellipsis", value: "More") { }
        }
    }

    private var legacyTabs: some View {
        TabView(selection: $tabPage) {
            layerTabView(layerSettings: $viewobject.allLayerSettings.intercityrail)
                .tabItem {
                    Label("Rail", systemImage: "tram.fill.tunnel")
                }
                .tag("Rail")

            layerTabView(layerSettings: $viewobject.allLayerSettings.localrail)
                .tabItem {
                    Label("Metro/Tram", systemImage: "lightrail.fill")
                }
                .tag("Metro/Tram")

            layerTabView(layerSettings: $viewobject.allLayerSettings.bus)
                .tabItem {
                    Label("Bus", systemImage: "bus.fill")
                }
                .tag("Bus")

            layerTabView(layerSettings: $viewobject.allLayerSettings.other)
                .tabItem {
                    Label("Other", systemImage: "ferry.fill")
                }
                .tag("Other")
        }
    }
}

class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if GlobalViewObject.showLayerSelector {
            return super.hitTest(point, with: event)
        }
        return nil
    }
}


extension View {
    /// Matches the Compose search field's Material surface, pill shape, and 4 dp shadow
    /// without requiring the newer Liquid Glass SDK.
    func catenarySearchBarSurface() -> some View {
        self
            .background(Color(uiColor: .systemBackground), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.14), radius: 4, x: 0, y: 2)
    }
}

struct HiddenSheetHeightMeasurer: View {
    @State private var showSheet = false
    var completion: (CGFloat) -> Void

    var body: some View {
        Color.clear
            .onAppear {
                showSheet = true
            }
            .sheet(isPresented: $showSheet) {
                SheetContent { height in
                    completion(height)
                    showSheet = false
                }
                .presentationDetents([.large])
                .interactiveDismissDisabled()
            }
    }

    struct SheetContent: View {
        var completion: (CGFloat) -> Void

        var body: some View {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        
                        DispatchQueue.main.async {
                            completion(geo.size.height)
                        }
                    }
            }
        }
    }
}


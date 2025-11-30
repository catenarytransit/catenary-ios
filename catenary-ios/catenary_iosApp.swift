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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
        
    var body: some Scene {
        WindowGroup {
            MainUIView()
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
            print("Measured .large detent height:", measuredHeight)

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
    var bigSheet: Bool {
        withAnimation {
            (viewobject.allLayerSettings[currentPage]?.visiblerealtimedots ?? true)
        }
    }
    var body: some View {
        EmptyView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inAppSearchOverlay(
                text: $viewobject.searchText,
                showField: $viewobject.showTopView,
                presDetent: viewobject.presDetent,
                confirmedEqual: viewobject.confirmedEqual
            )
            .sheet(isPresented: $viewobject.showLayerSelector) {
                
                NavigationStack {
                    LayerSelectorSheet(tabPage: $currentPage)
                        .presentationDetents([.height(250 + (bigSheet ? 200 : 0))])
                        .presentationBackgroundInteraction(PresentationBackgroundInteraction.disabled)
                        .interactiveDismissDisabled(false)
                        .toolbar {
                            
                            ToolbarItem(placement: .topBarLeading) {
                                Text("Layer Settings: \(Text(currentPage).foregroundColor(.catenaryBlue))")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .fixedSize()
                            }
                            .sharedBackgroundVisibility(.hidden)
                            
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
    var label: String
    var sfsymbol: Bool = false
    var body: some View {
        VStack {
            Button {
                withAnimation(nil) {
                    specificLayerSetting.toggle()
                }
            } label: {
                (sfsymbol ? Image(systemName: imageName) : Image(imageName).resizable())
                    
                    
                    .if(sfsymbol) { $0.padding() }
                    .foregroundStyle(Color.primary)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.thinMaterial)
                            
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(specificLayerSetting ? Color.catenaryBlue : Color.clear, lineWidth: 3)
                    )
                    .animation(nil, value: specificLayerSetting)
            }
            .layoutPriority(-1)
            Text(label)
                .lineLimit(1, reservesSpace: true)
                .layoutPriority(0)
//                .minimumScaleFactor(0.3)
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct layerTabView: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @Binding var layerSettings: LayerCategorySettings
    @State var selected: Int = 0
    var body: some View {
        
        VStack {
            HStack(alignment: .firstTextBaseline) {
                layerSettingButton(specificLayerSetting: $layerSettings.shapes, imageName: "routesicon", label: "Routes")
                layerSettingButton(specificLayerSetting: $layerSettings.labelshapes, imageName: "labelsicon", label: "Labels")
                layerSettingButton(specificLayerSetting: $layerSettings.stops, imageName: "stopsicon", label: "Stops")
                layerSettingButton(specificLayerSetting: $layerSettings.labelstops, imageName: "\(colorScheme == .dark ? "dark" : "light")-stop-name", label: "Names")
                layerSettingButton(specificLayerSetting: $layerSettings.visiblerealtimedots, imageName: "vehiclesicon", label: "Vehicles")
            }
            .padding(.horizontal)
            .layoutPriority(1)
            
            if layerSettings.visiblerealtimedots {
                Grid() {
                    
                    // Top row: 5 buttons
                    GridRow {
                        
                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.route,
                                           imageName: "point.bottomleft.forward.to.point.topright.scurvepath",
                                           label: "Route", sfsymbol: true)
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(3)
                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.trip,
                                           imageName: "point.topleft.down.to.point.bottomright.curvepath",
                                           label: "Trip", sfsymbol: true)
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(3)
                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.vehicle,
                                           imageName: "cablecar",
                                           label: "Vehicle", sfsymbol: true)
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(3)
                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.delay,
                                           imageName: "stopwatch",
                                           label: "Delay", sfsymbol: true)
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(3)
                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.speed,
                                           imageName: "gauge.with.dots.needle.67percent",
                                           label: "Speed", sfsymbol: true)
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(3)
                    }
                    
                    // Bottom row: 3 buttons, centered
                    GridRow {
                        //                    Spacer()
                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.occupancy,
                                           imageName: "person.2",
                                           label: "Occupancy", sfsymbol: true)
                        .gridCellColumns(5)
                        .frame(maxWidth: .infinity)
                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.headsign,
                                           imageName: "flag.pattern.checkered",
                                           label: "Headsign", sfsymbol: true)
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(5)
                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.direction,
                                           imageName: "line.diagonal.arrow",
                                           label: "Direction", sfsymbol: true)
                        .gridCellColumns(5)
                        .frame(maxWidth: .infinity)
                        //                    Spacer()
                    }
                }
                .padding()
            }
            

            
//            HStack(alignment: .firstTextBaseline) {
//                //direction always true
//                layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.route, imageName: "point.bottomleft.forward.to.point.topright.scurvepath", label: "Route", sfsymbol: true)
//                layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.trip, imageName: "point.topleft.down.to.point.bottomright.curvepath", label: "Trip", sfsymbol: true)
//                layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.vehicle, imageName: "cablecar", label: "Vehicle", sfsymbol: true)
//                layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.headsign, imageName: "flag.pattern.checkered", label: "Headsign", sfsymbol: true)
//                layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.speed, imageName: "gauge.with.dots.needle.67percent", label: "Speed", sfsymbol: true)
//                layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.occupancy, imageName: "person.3", label: "Occupancy", sfsymbol: true)
//                layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.delay, imageName: "stopwatch", label: "Delay", sfsymbol: true)
//                layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.direction, imageName: "line.diagonal.arrow", label: "Direction", sfsymbol: true)
//                
//            }
//            .padding()
            
//            if layerSettings.visiblerealtimedots {
//                Spacer()
//                    .frame(height: 150)
//            }
        }
    }
}

struct LayerSelectorSheet: View {
    
    @EnvironmentObject var viewobject: viewObject
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @Binding var tabPage: String
    
    var body: some View {
        
    
            
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
            
            Tab("More", systemImage: "ellipsis", value: "More") {
                
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .symbolColorRenderingMode(.flat)
        .tint(.catenaryBlue)
//        .tabViewStyle(.page(indexDisplayMode: .never))

//        .toolbar {
//            ToolbarItem(placement: .bottomBar) {
//                Label("Rail", systemImage: "tram.fill.tunnel")
//            }
//            ToolbarItem(placement: .bottomBar) {
//                Label("Rail", systemImage: "tram.fill.tunnel")
//            }
//        }
    

    }
}

class PassThroughWindow: UIWindow {
    // textfield rame
    var textFieldFrame: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // When showing the layer selector sheet, this window should capture touches normally
        if GlobalViewObject.showLayerSelector {
            return super.hitTest(point, with: event)
        }

        // Otherwise, allow touches to pass through except within the text field frame
        if textFieldFrame.contains(point) {
            // Still pass through touches in the text field area so the underlying search field can be focused
            return nil
        }

        // Pass through touches elsewhere to the main app window
        return nil
    }
}






struct InAppNotificationViewModifier: ViewModifier {
    @Binding var text: String
    @Binding var showField: Bool
    var presDetent: PresentationDetent
    var confirmedEqual: Bool
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showField && !confirmedEqual {
                    TextField("Search Here", text: $text)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .capsule)
                        .padding()
                        .ignoresSafeArea(.container, edges: .bottom)
                        .background (
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        if let windowScene = UIApplication.shared.connectedScenes
                                            .compactMap({ $0 as? UIWindowScene })
                                            .first,
                                           let window = windowScene.windows.last as? PassThroughWindow {
                                            // Convert frame to window coordinates
                                            let frameInWindow = geo.frame(in: .global)
                                            window.textFieldFrame = frameInWindow
                                        }
                                    }
                            }
                        )
                        .transition(.blurReplace)
                }
            }
    }
}

extension View {
    func inAppSearchOverlay(text: Binding<String>, showField: Binding<Bool>, presDetent: PresentationDetent, confirmedEqual: Bool) -> some View {
        self.modifier(InAppNotificationViewModifier(text: text, showField: showField, presDetent: presDetent, confirmedEqual: confirmedEqual))
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


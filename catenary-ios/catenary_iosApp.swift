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
//    @StateObject var liveTransitData: TransitViewModel = TransitViewModel()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
        
    var body: some Scene {
        WindowGroup {
            MainUIView()
                .environmentObject(viewobject)
                .onAppear() {
                    let url = URL(string: "wss://echo.websocket.org")!
                    let task = URLSession.shared.webSocketTask(with: url)
                    task.resume()
                    
                    task.send(.string("Hello WebSocket")) { error in
                        if let error = error {
                            print("Send error:", error)
                        }
                    }
                    
                    task.receive { result in
                        switch result {
                        case .success(let message):
                            switch message {
                            case .string(let text):
                                print("Received:", text)
                            case .data(let data):
                                print("Received data:", data)
                            @unknown default:
                                break
                            }
                        case .failure(let error):
                            print("Receive error:", error)
                        }
                    }
                    
                }
            
            
//                .environmentObject(liveTransitData)
//                .onAppear {
//                    liveTransitData.loadData()
//                    
//                }
//                .onTapGesture {
//                    liveTransitData.vehicles.forEach {
//                        print("\($0.agencyName), \($0.type) — \($0.headsign), \($0.routeId)")
//                        
//                    }
//                }
            
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
//    var bigSheet: Bool {
//        withAnimation {
//            (viewobject.allLayerSettings[currentPage]?.visiblerealtimedots ?? true)
//        }
//    }
//    @State var expanded: Bool = false
    var body: some View {
        EmptyView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inAppSearchOverlay(
                text: $viewobject.searchText,
                showField: $viewobject.showTopView,
                presDetent: viewobject.presDetent,
                confirmedEqual: viewobject.confirmedEqual, 
                keyboardVisible: viewobject.isVisible
            )
            .sheet(isPresented: $viewobject.showLayerSelector) {
                
                NavigationStack {
                    LayerSelectorSheet(tabPage: $currentPage)
                        .presentationDetents([.height(230)])
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
                            .stroke(specificLayerSetting ? Color.catenaryBlue : Color.clear, lineWidth: 3)
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
    @State var selected: Int = 0
    
    var body: some View {
        
        VStack {
            HStack(alignment: .firstTextBaseline) {
                layerSettingButton(specificLayerSetting: $layerSettings.shapes, imageName: "routesicon", label: "Routes")
                layerSettingButton(specificLayerSetting: $layerSettings.labelshapes, imageName: "labelsicon", label: "Labels")
                layerSettingButton(specificLayerSetting: $layerSettings.stops, imageName: "stopsicon", label: "Stops")
                layerSettingButton(specificLayerSetting: $layerSettings.labelstops, imageName: "\(colorScheme == .dark ? "dark" : "light")-stop-name", label: "Names")
                layerSettingButton(specificLayerSetting: $layerSettings.visiblerealtimedots, imageName: "vehiclesicon", label: "Vehicles")
                    .contextMenu {
                        Toggle(isOn: $layerSettings.labelrealtimedots.route) {
                            Label("Route", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                        }

                        Toggle(isOn: $layerSettings.labelrealtimedots.trip) {
                            Label("Trip", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }

                        Toggle(isOn: $layerSettings.labelrealtimedots.vehicle) {
                            Label("Vehicle", systemImage: "cablecar")
                        }

                        Toggle(isOn: $layerSettings.labelrealtimedots.delay) {
                            Label("Delay", systemImage: "stopwatch")
                        }

                        Toggle(isOn: $layerSettings.labelrealtimedots.occupancy) {
                            Label("Occupancy", systemImage: "person.3")
                        }

                        Toggle(isOn: $layerSettings.labelrealtimedots.speed) {
                            Label("Speed", systemImage: "gauge.with.dots.needle.67percent")
                        }

                        Toggle(isOn: $layerSettings.labelrealtimedots.headsign) {
                            Label("Headsign", systemImage: "flag.pattern.checkered")
                        }

                        Toggle(isOn: $layerSettings.labelrealtimedots.direction) {
                            Label("Direction", systemImage: "line.diagonal.arrow")
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
            }
            .padding(.horizontal)
            
//            DisclosureGroup(isExpanded: $expandedVehicleSettings) {
//                
////                layerSettingButton(specificLayerSetting: $layerSettings.visiblerealtimedots, imageName: "vehiclesicon", label: "Vehicles")
//                Text("Hello! I am a setting.")
//                Text("I am also a setting.")
//                Text("I, too, exist as a setting in this world!")
//                Text("I exist?")
//            } label: {
//                HStack {
//                    Image(systemName: "arrow.down")
//                    Text("Vehicle Options")
//                    Image(systemName: "arrow.down")
//                }
//                .frame(maxWidth: .infinity)
//            }
//            .labelsHidden()
//                if layerSettings.visiblerealtimedots {
                    
//            ScrollView(.horizontal) {
//                    HStack {
////                        
//                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.route,
//                                           imageName: "point.bottomleft.forward.to.point.topright.scurvepath",
//                                           label: "Route", sfsymbol: true)
//                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.trip,
//                                           imageName: "point.topleft.down.to.point.bottomright.curvepath",
//                                           label: "Trip", sfsymbol: true)
//                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.vehicle,
//                                           imageName: "cablecar",
//                                           label: "Vehicle", sfsymbol: true)
//                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.delay,
//                                           imageName: "stopwatch",
//                                           label: "Delay", sfsymbol: true)
//                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.occupancy,
//                                           imageName: "person.3",
//                                           label: "Occupancy", sfsymbol: true)
//                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.speed,
//                                           imageName: "gauge.with.dots.needle.67percent",
//                                           label: "Speed", sfsymbol: true)
//                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.headsign,
//                                           imageName: "flag.pattern.checkered",
//                                           label: "Headsign", sfsymbol: true)
//                        layerSettingButton(specificLayerSetting: $layerSettings.labelrealtimedots.direction,
//                                           imageName: "line.diagonal.arrow",
//                                           label: "Direction", sfsymbol: true)
//                        //                    Spacer()
//                    }
//                    .padding(.horizontal)
//                    .padding(.vertical, 5)
//                    }
//                    .scrollIndicators(.never)
////                    .border(.black, width: 1)
//                    .scrollBounceBehavior(.always)
                    
                    
//
//            }
            

            
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
        
        if GlobalViewObject.showLayerSelector {
            return super.hitTest(point, with: event)
        }

        
        if textFieldFrame.contains(point) {
        
            return nil
        }

        
        return nil
    }
}






struct InAppNotificationViewModifier: ViewModifier {
    @Binding var text: String
    @Binding var showField: Bool
    var presDetent: PresentationDetent
    var confirmedEqual: Bool
    var keyboardVisible: Bool
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showField && !(confirmedEqual || keyboardVisible) {
                    TextField("Search Here", text: $text)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.interactive(), in: .capsule)
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
    func inAppSearchOverlay(text: Binding<String>, showField: Binding<Bool>, presDetent: PresentationDetent, confirmedEqual: Bool, keyboardVisible: Bool) -> some View {
        self.modifier(InAppNotificationViewModifier(text: text, showField: showField, presDetent: presDetent, confirmedEqual: confirmedEqual, keyboardVisible: keyboardVisible))
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


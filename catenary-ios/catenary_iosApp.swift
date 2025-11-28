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

    var body: some View {
        EmptyView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inAppSearchOverlay(
                text: $viewobject.searchText,
                showField: $viewobject.showTopView,
                presDetent: viewobject.presDetent,
                confirmedEqual: viewobject.confirmedEqual
            )
    }
}

class PassThroughWindow: UIWindow {
    // textfield rame
    var textFieldFrame: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
         
        if textFieldFrame.contains(point) {
            print("TextField area tapped at: \(point)")
            return nil // returning nil still passes the touch through
        }

        // else, tap is outside — pass through to main app
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


import SwiftUI

@main
struct WarpKeyApp: App {
    @StateObject private var hotKeyManager = AppHotKeyManager()
    @StateObject private var launchManager = LaunchAtLoginManager()
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        let _ = {
            // Assign the openWindow action to the delegate. This is still important
            // for later programmatic window opening (e.g., from notifications).
            appDelegate.openWindowAction = openWindow
        }()

        Window("WarpKey", id: "main-menu") {
            MenuView(manager: hotKeyManager, launchManager: launchManager)
                // ✅ Provide settings as an EnvironmentObject
                .environmentObject(appDelegate.settings)
                // ✅ WindowAccessor is now responsible for initial visibility based on settings
                .background(WindowAccessor()) // No need for expectedContentSize here
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize) // Let SwiftUI manage the window size based on content
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .windowList) {} // Hide default Window menu items
        }
    }
}

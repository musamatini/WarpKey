// WarpKeyApp.swift
import SwiftUI

@main
struct WarpKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var launchManager = LaunchAtLoginManager()
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        let settings = appDelegate.settings
        let hotKeyManager = appDelegate.hotKeyManager
        let _ = { appDelegate.openWindowAction = openWindow }()

        Window("WarpKey", id: "main-menu") {
            // Pass the single, correct instances to our views.
            MenuView(manager: hotKeyManager, launchManager: launchManager)
                .environmentObject(settings)
                .background(WindowAccessor()) // Assuming WindowAccessor is a helper you have
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands { CommandGroup(replacing: .windowList) {} }
    }
} 

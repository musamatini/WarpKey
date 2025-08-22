// warpkeyapp.swift

import SwiftUI
import AppKit
import Sparkle
import Combine

// RootView.swift

import SwiftUI
import AppKit
import Sparkle
import Combine

struct RootView: View {
    @ObservedObject var settings: SettingsManager
    let appDelegate: AppDelegate
    @StateObject private var launchManager = LaunchAtLoginManager()
    @State private var showMigrationAlert = false

    private var preferredColorScheme: ColorScheme? {
        switch settings.colorScheme {
        case .light: return .light
        case .dark: return .dark
        case .auto: return settings.systemColorScheme
        }
    }

    var body: some View {
        ZStack {
            if !settings.hasCompletedOnboarding {
                WelcomePage(
                    manager: appDelegate.hotKeyManager,
                    onGetStarted: {
                        if !appDelegate.hotKeyManager.hasAccessibilityPermissions {
                            AccessibilityManager.requestPermissions()
                        }
                        settings.hasCompletedOnboarding = true
                    },
                    onGoToHelp: { settings.hasCompletedOnboarding = true; NotificationCenter.default.post(name: .goToHelpPageInMainWindow, object: nil) }
                )
            } else if !appDelegate.hotKeyManager.hasAccessibilityPermissions {
                PermissionsRestartRequiredView()
            } else if !appDelegate.hotKeyManager.hasScreenRecordingPermissions && !settings.hasSkippedScreenRecordingPermission {
                ScreenRecordingPermissionRequiredView()
            } else {
                MenuView(
                    manager: appDelegate.hotKeyManager,
                    launchManager: launchManager,
                    updaterViewModel: appDelegate.updaterViewModel
                )
            }
        }
        .environmentObject(settings)
        .preferredColorScheme(preferredColorScheme)
        .animation(.default, value: settings.hasCompletedOnboarding)
        .animation(.default, value: appDelegate.hotKeyManager.hasAccessibilityPermissions)
        .animation(.default, value: appDelegate.hotKeyManager.hasScreenRecordingPermissions)
        .animation(.default, value: settings.hasSkippedScreenRecordingPermission)
        .onReceive(settings.$didPerformMigration) { migrationOccurred in
            if migrationOccurred {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.showMigrationAlert = true
                }
            }
        }
        .alert("Update Complete!", isPresented: $showMigrationAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your settings have been migrated from the old app name, WrapKey, to the new WarpKey.")
            + Text("\n\nTo avoid confusion, you can remove the old 'WrapKey' entry from Accessibility in System Settings. This new version, 'WarpKey', will use its own entry.")
            + Text("\n\nYou can now safely rename the app in your Applications folder from \"WrapKey.app\" to \"WarpKey.app\" if you wish.")
        }
    }
}


struct AppCommands: Commands {
    private func showAppSettings() {
        NSApp.sendAction(#selector(AppDelegate.showPreferences), to: nil, from: nil)
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                showAppSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

@main
struct WarpKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
        }
        .commands {
            AppCommands()
            CommandMenu("Help") {
                Button("WarpKey Help") {
                    if let window = NSApp.mainWindow, window.isVisible {
                        NotificationCenter.default.post(name: .goToHelpPageInMainWindow, object: nil)
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    } else {
                        appDelegate.handleOpenMainWindow()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                             NotificationCenter.default.post(name: .goToHelpPageInMainWindow, object: nil)
                        }
                    }
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}

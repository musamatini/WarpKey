import AppKit
import SwiftUI
import UserNotifications
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    var statusItem: NSStatusItem?
    let settings = SettingsManager() // SettingsManager should be able to persist the onboarding status
    private var settingsCancellable: AnyCancellable?

    var openWindowAction: OpenWindowAction? // This will be set by WarpKeyApp

    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        // 1. Setup notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // 2. Determine initial activation policy based on onboarding status.
        // This policy determines if the app appears in the Dock or runs as an accessory.
        if !settings.hasCompletedOnboarding {
            NSApp.setActivationPolicy(.regular) // Stay visible for onboarding (appears in Dock)
            print("[LIFECYCLE] First launch detected. Setting activation policy to .regular.")
            // IMPORTANT: We do NOT open the window directly here.
            // The opening logic will be in WarpKeyApp.swift where `openWindow` is available.
        } else {
            NSApp.setActivationPolicy(.accessory) // Run in background (no Dock icon)
            print("[LIFECYCLE] Standard launch. Setting activation policy to .accessory.")
        }

        // 3. Setup notification system
        checkAndRequestNotificationPermissions()

        // 4. Create a subscription to the setting that controls menu bar icon visibility.
        settingsCancellable = settings.$showMenuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                if isVisible {
                    self?.createStatusItem()
                } else {
                    self?.statusItem?.isVisible = false
                }
            }
        
        // 5. Initial setup of the icon based on the loaded setting.
        if settings.showMenuBarIcon {
            createStatusItem()
        }
        
        // Notification observers (unchanged, good for inter-component communication)
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenMainWindow), name: .openMainWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenMainWindowOnboardingCompleteAndGoToHelp), name: .goToHelpPageInMainWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenMainWindowOnboardingComplete), name: .openMainWindowOnboardingComplete, object: nil)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        print("[LIFECYCLE] Last window closed, but app will continue running in the background.")
        // This is crucial for menu bar apps: don't terminate when windows are closed.
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // This method is called when clicking the Dock icon (if policy is .regular).
        // It should *always* bring the app to the front and open the main window.
        print("[LIFECYCLE] Application reopened via Dock. Activating and opening main window.")
        NSApp.setActivationPolicy(.regular) // Ensure it's regular to show Dock icon and window
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?(id: "main-menu") // Open/bring to front the main window
        return true
    }
    
    // MARK: - Menu Bar Item (Status Item)
    
    @objc func createStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = statusItem?.button {
                button.image = NSImage(named: "MenuBarIcon")
                button.action = #selector(statusBarButtonClicked)
                button.toolTip = "WarpKey" // Good practice to add a tooltip
            }
        }
        statusItem?.isVisible = true
    }
    
    @objc func statusBarButtonClicked() {
        // When menu bar icon is clicked, activate the app and open the main window.
        print("[LIFECYCLE] Menu bar icon clicked. Activating and opening main window.")
        NSApp.setActivationPolicy(.regular) // Bring to front (will show Dock icon temporarily if not already)
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?(id: "main-menu") // Open/bring to front the main window
    }
    
    // MARK: - Notification Handlers for Windows (mostly unchanged)
    @objc private func handleOpenMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?(id: "main-menu")
    }

    @objc private func handleOpenMainWindowOnboardingComplete() {
        // After onboarding, the user might expect the app to transition to menu-bar-only mode.
        // If the user *explicitly* completes onboarding and clicks a button,
        // we should ensure the activation policy is set correctly for future launches.
        // This won't change the *current* launch's policy, only the next.
        // The `applicationDidFinishLaunching` logic will handle the actual policy on restart.
        NSApp.setActivationPolicy(.regular) // Ensure window comes to front
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?(id: "main-menu")
        
        // After onboarding, if the user opts for menu bar only, the app should be accessory on next launch.
        // This relies on `settings.hasCompletedOnboarding` being true.
    }
    
    @objc private func handleOpenMainWindowOnboardingCompleteAndGoToHelp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?(id: "main-menu")
        NotificationCenter.default.post(name: .goToHelpPageInMainWindow, object: nil)
    }

    // MARK: - User Notifications (Unchanged)
    
    private func checkAndRequestNotificationPermissions() {
        NotificationManager.shared.checkAuthorizationStatus { status in
            switch status {
            case .notDetermined: self.showPrePermissionAlert()
            default: break
            }
        }
    }
    
    private func showPrePermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Enable Notifications?"
        alert.informativeText = "Get notified when shortcuts are assigned. This helps confirm your changes worked."
        alert.addButton(withTitle: "Allow Notifications")
        alert.addButton(withTitle: "Not Now")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NotificationManager.shared.requestUserPermission { _ in }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        if response.actionIdentifier == "OPEN_ACTION" {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openWindowAction?(id: "main-menu")
        }
        completionHandler()
    }
}

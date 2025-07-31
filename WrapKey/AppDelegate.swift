//AppDelegate.swift
import AppKit
import SwiftUI
import UserNotifications
import Combine
import QuartzCore
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, SPUUpdaterDelegate {

    // MARK: - Properties
    var statusItem: NSStatusItem?
    
    var settings: SettingsManager!
    var hotKeyManager: AppHotKeyManager!
    
    private var settingsCancellable: AnyCancellable?
    var openWindowAction: OpenWindowAction?
    
    // MARK: - Sparkle Updater (Corrected with lazy var)

    lazy var updaterController: SPUStandardUpdaterController = {
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }()
    
    lazy var updaterViewModel: UpdaterViewModel = {
        return UpdaterViewModel(updater: self.updaterController.updater)
    }()
    
    // MARK: - Initialization
    override init() {
        super.init()
    }

    // MARK: - NSApplicationDelegate Lifecycle
    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        settings.setupAppearanceMonitoring()
        
        UNUserNotificationCenter.current().delegate = self
        checkNotificationStatusAndWarnIfNeeded()

        if settings.hasCompletedOnboarding {
            NSApp.setActivationPolicy(.accessory)
        }

        settingsCancellable = settings.$showMenuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                if isVisible {
                    self?.createStatusItem()
                } else {
                    if let item = self?.statusItem {
                        NSStatusBar.system.removeStatusItem(item)
                        self?.statusItem = nil
                    }
                }
            }
        
        if settings.showMenuBarIcon {
            createStatusItem()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenMainWindow), name: .openMainWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleGoToHelpPage), name: .goToHelpPageInMainWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutActivation), name: .shortcutActivated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRestartRequest), name: .requestAppRestart, object: nil)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?(id: "main-menu")
        return true
    }
    
    // MARK: - App Control
    @objc func handleRestartRequest() {
        let appPath = Bundle.main.bundlePath
        let script = "sleep 1 && open \"\(appPath)\""

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]

        // This prevents the new process from being a child of the old one
        // which is crucial for a clean restart.
        task.standardError = nil
        task.standardInput = nil
        task.standardOutput = nil
        
        do {
            try task.run()
            NSApp.terminate(self)
        } catch {
            print("Failed to run restart script: \(error)")
        }
    }
    
    // MARK: - Permissions
    func checkNotificationStatusAndWarnIfNeeded() {
        let center = UNUserNotificationCenter.current()
        
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    self.requestInitialPermission(center: center)
                
                case .denied:
                    self.showPermissionDeniedAlert()

                case .authorized, .provisional, .ephemeral:
                    break

                @unknown default:
                    break
                }
            }
        }
    }
    
    private func requestInitialPermission(center: UNUserNotificationCenter) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error.localizedDescription)")
            }
        }
    }

    private func showPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Notifications Disabled"
        alert.informativeText = "To receive confirmations for background actions like importing settings or assigning apps, please enable notifications for WrapKey in System Settings."
        alert.alertStyle = .warning
        
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - Menu Bar Item
    @objc func createStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = statusItem?.button {
                button.wantsLayer = true
                
                if let customIcon = NSImage(named: "MenuBarIcon") {
                    customIcon.isTemplate = true
                    button.image = customIcon
                } else {
                    button.image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "WrapKey")
                }
                
                button.action = #selector(statusBarButtonClicked)
                button.toolTip = "WrapKey"
            }
        }
        statusItem?.isVisible = true
    }

    @objc func statusBarButtonClicked() {
        let mainWindow = NSApplication.shared.windows.first { $0.title == "WrapKey" }

        if let window = mainWindow, window.isVisible {
            window.close()
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openWindowAction?(id: "main-menu")
        }
    }

    // MARK: - Notification Handlers
    @objc func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.title == "WrapKey" else {
            return
        }
        
        if settings.hasCompletedOnboarding {
            NSApp.setActivationPolicy(.accessory)
        }
    }
        
    @objc private func handleOpenMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func handleGoToHelpPage() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleShortcutActivation() {
        guard let button = statusItem?.button, button.layer?.animation(forKey: "bounce") == nil else { return }
        
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1.0, 1.25, 0.85, 1.1, 0.95, 1.0]
        animation.duration = 0.4
        animation.timingFunctions = (0..<5).map { _ in CAMediaTimingFunction(name: .easeInEaseOut) }
        button.layer?.add(animation, forKey: "bounce")
    }

    @objc private func handleAppDidBecomeActive() {
        hotKeyManager.restartMonitoringIfNeeded()
    }
    
    // MARK: - Sparkle Updater Delegate (Gentle Reminders)
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem, for anUpdateCheck: SPUUpdateCheck, state: SPUUserUpdateState, acknowledgement: @escaping (SPUUserUpdateChoice) -> Void) {
        if NSApp.activationPolicy() == .accessory {
            NotificationManager.shared.sendUpdateAvailableNotification(version: item.displayVersionString)
            acknowledgement(.dismiss)
        } else {
            acknowledgement(.install)
        }
    }

    // MARK: - User Notification Center Delegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "OPEN_ACTION":
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openWindowAction?(id: "main-menu")
        case "UPDATE_ACTION":
            updaterController.checkForUpdates(nil)
        default:
            break
        }
        completionHandler()
    }
}

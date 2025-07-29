//AppDelegate.swift
import AppKit
import SwiftUI
import UserNotifications
import Combine
import QuartzCore

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    // MARK: - Properties
    var statusItem: NSStatusItem?
    
    private(set) var settings: SettingsManager
    private(set) var hotKeyManager: AppHotKeyManager
    
    private var settingsCancellable: AnyCancellable?
    var openWindowAction: OpenWindowAction?

    // MARK: - Initialization
    override init() {
        let settingsManager = SettingsManager()
        self.settings = settingsManager
        self.hotKeyManager = AppHotKeyManager(settings: settingsManager)
        super.init()
    }

    // MARK: - NSApplicationDelegate Lifecycle
    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        if settings.hasCompletedOnboarding {
            NSApp.setActivationPolicy(.accessory)
        }

        UNUserNotificationCenter.current().delegate = self

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
                    button.image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "WarpKey")
                }
                
                button.action = #selector(statusBarButtonClicked)
                button.toolTip = "WarpKey"
            }
        }
        statusItem?.isVisible = true
    }

    @objc func statusBarButtonClicked() {
        let mainWindow = NSApplication.shared.windows.first { $0.title == "WarpKey" }

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
        guard let window = notification.object as? NSWindow, window.title == "WarpKey" else {
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
        NotificationCenter.default.post(name: .goToHelpPageInMainWindow, object: nil)
    }

    @objc private func handleShortcutActivation() {
        guard let button = statusItem?.button, button.layer?.animation(forKey: "bounce") == nil else { return }
        
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1.0, 1.25, 0.85, 1.1, 0.95, 1.0]
        animation.duration = 0.4
        animation.timingFunctions = (0..<5).map { _ in CAMediaTimingFunction(name: .easeInEaseOut) }
        button.layer?.add(animation, forKey: "bounce")
    }

    // MARK: - User Notification Center Delegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "OPEN_ACTION" {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openWindowAction?(id: "main-menu")
        }
        completionHandler()
    }
}

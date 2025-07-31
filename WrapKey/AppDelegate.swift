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
    private var updateCheckTimer: Timer?

    // MARK: - Sparkle Updater
    lazy var updaterController: SPUStandardUpdaterController = {
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.updateCheckInterval = 6 * 60 * 60 // 6 hours
        return controller
    }()
    
    lazy var updaterViewModel: UpdaterViewModel = {
        return UpdaterViewModel(updater: self.updaterController.updater)
    }()
    
    // MARK: - NSApplicationDelegate Lifecycle
    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        settings.setupAppearanceMonitoring()
        
        UNUserNotificationCenter.current().delegate = self
        
        if settings.hasCompletedOnboarding {
            NSApp.setActivationPolicy(.accessory)
            updaterController.updater.checkForUpdatesInBackground()
        }

        settingsCancellable = settings.$showMenuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                if isVisible {
                    self?.createStatusItem()
                } else {
                    self?.removeStatusItem()
                }
            }
        
        if settings.showMenuBarIcon {
            createStatusItem()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenMainWindow), name: .openMainWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutActivation), name: .shortcutActivated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRestartRequest), name: .requestAppRestart, object: nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        updateCheckTimer?.invalidate()
        updateCheckTimer = nil
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
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1 && open \"\(appPath)\""]
        
        do {
            try task.run()
            NSApp.terminate(self)
        } catch {
            print("Failed to run restart script: \(error)")
        }
    }
    
    // MARK: - Menu Bar Item
    func createStatusItem() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.wantsLayer = true
            let icon = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "WrapKey")
            icon?.isTemplate = true
            button.image = icon
            button.action = #selector(statusBarButtonClicked)
            button.toolTip = "WrapKey"
        }
        statusItem?.isVisible = true
    }
    
    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc func statusBarButtonClicked() {
        let menu = NSMenu()

        menu.addItem(withTitle: "Open WrapKey", action: #selector(handleOpenMainWindow), keyEquivalent: "")
        menu.addItem(.separator())
        
        let allAssignments = settings.currentProfile.wrappedValue.assignments
        if allAssignments.isEmpty {
            let noShortcutsItem = NSMenuItem(title: "No shortcuts configured.", action: nil, keyEquivalent: "")
            noShortcutsItem.isEnabled = false
            menu.addItem(noShortcutsItem)
        } else {
            for assignment in allAssignments.sorted(by: { (hotKeyManager.getDisplayName(for: $0.configuration.target) ?? "") < (hotKeyManager.getDisplayName(for: $1.configuration.target) ?? "") }) {
                let title = hotKeyManager.getDisplayName(for: assignment.configuration.target) ?? "Unknown Shortcut"
                let menuItem = NSMenuItem(title: title, action: #selector(menuItemTriggered(_:)), keyEquivalent: "")
                menuItem.representedObject = assignment
                menuItem.image = hotKeyManager.getIcon(for: assignment.configuration.target)
                menu.addItem(menuItem)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit WrapKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        statusItem?.popUpMenu(menu)
    }
    
    @objc func menuItemTriggered(_ sender: NSMenuItem) {
        guard let assignment = sender.representedObject as? Assignment else { return }
        _ = hotKeyManager.handleActivation(assignment: assignment)
    }

    // MARK: - Notification Handlers
    @objc func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.title == "WrapKey" else { return }
        if settings.hasCompletedOnboarding {
            NSApp.setActivationPolicy(.accessory)
        }
    }
        
    @objc func handleOpenMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?(id: "main-menu")
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
    
    // MARK: - Sparkle Updater Delegate
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem, for anUpdateCheck: SPUUpdateCheck, state: SPUUserUpdateState, acknowledgement: @escaping (SPUUserUpdateChoice) -> Void) {
        if NSApp.activationPolicy() == .accessory {
            NotificationManager.shared.sendUpdateAvailableNotification(version: item.displayVersionString)
            acknowledgement(.dismiss)
        } else {
            acknowledgement(.install)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        // Intentionally left blank to suppress "You're up to date" alerts.
    }

    // MARK: - User Notification Center Delegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "OPEN_ACTION":
            handleOpenMainWindow()
        case "UPDATE_ACTION":
            updaterController.checkForUpdates(nil)
        default:
            break
        }
        completionHandler()
    }
}

private extension Bundle {
    var versionString: String {
        return object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
    }
}

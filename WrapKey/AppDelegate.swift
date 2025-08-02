// AppDelegate.swift
import AppKit
import SwiftUI
import UserNotifications
import Combine
import QuartzCore
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, SPUUpdaterDelegate {

    var mainWindow: NSWindow?
    var statusItem: NSStatusItem?
    var cheatsheetWindow: NSWindow?

    let settings = SettingsManager()
    lazy var hotKeyManager = AppHotKeyManager(settings: settings)

    private var settingsCancellable: AnyCancellable?
    var openWindowAction: OpenWindowAction?
    private var updateCheckTimer: Timer?

    lazy var updaterController: SPUStandardUpdaterController = {
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.updateCheckInterval = 6 * 60 * 60
        return controller
    }()

    lazy var updaterViewModel: UpdaterViewModel = {
        return UpdaterViewModel(updater: self.updaterController.updater)
    }()

    // --- DELEGATE METHODS ---
    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        handleOpenMainWindow()
        
        settings.setupAppearanceMonitoring()
        UNUserNotificationCenter.current().delegate = self
        
        updaterController.updater.checkForUpdatesInBackground()

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
        
        NotificationCenter.default.addObserver(forName: .showCheatsheet, object: nil, queue: .main) { [weak self] _ in
            self?.showCheatsheet()
        }
        NotificationCenter.default.addObserver(forName: .hideCheatsheet, object: nil, queue: .main) { [weak self] _ in
            self?.hideCheatsheet()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateCheckTimer?.invalidate()
        updateCheckTimer = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        handleOpenMainWindow()
        return true
    }
    
    // --- CUSTOM METHODS ---

    @objc func handleOpenMainWindow() {
        if mainWindow == nil {
            class KeyWindow: NSWindow {
                override var canBecomeKey: Bool { return true }
            }

            let window = KeyWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 700),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            window.center()
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            
            let rootView = RootView(settings: self.settings, appDelegate: self)
            let hostingView = NSHostingView(rootView: rootView)
            window.contentView = hostingView
            
            window.initialFirstResponder = hostingView
            
            self.mainWindow = window
        }
        
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

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

    @objc func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        
        NSApp.setActivationPolicy(.accessory)
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

    // --- CHEATSHEET WINDOW ---
    func createCheatsheetWindow() {
        guard cheatsheetWindow == nil else { return }

        let cheatsheetView = CheatsheetView(manager: hotKeyManager)
            .environmentObject(settings)

        let window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.contentView = NSHostingView(rootView: cheatsheetView)
        
        self.cheatsheetWindow = window
    }

    func showCheatsheet() {
        if cheatsheetWindow == nil {
            createCheatsheetWindow()
        }
        
        guard let window = cheatsheetWindow, !window.isVisible, let screen = NSScreen.main else { return }
        
        // Made bigger to accommodate more columns as requested.
        let cheatsheetSize = CGSize(width: screen.visibleFrame.width * 0.9, height: screen.visibleFrame.height * 0.8)
        window.setContentSize(cheatsheetSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func hideCheatsheet() {
        cheatsheetWindow?.orderOut(nil)
    }

    // --- UPDATER AND NOTIFICATIONS ---
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem, for anUpdateCheck: SPUUpdateCheck, state: SPUUserUpdateState, acknowledgement: @escaping (SPUUserUpdateChoice) -> Void) {
        if NSApp.activationPolicy() == .accessory {
            NotificationManager.shared.sendUpdateAvailableNotification(version: item.displayVersionString)
            acknowledgement(.dismiss)
        } else {
            acknowledgement(.install)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
    }

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

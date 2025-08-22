// AppDelegate.swift

import AppKit
import SwiftUI
import UserNotifications
import Combine
import QuartzCore
import Sparkle

final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates: Bool

    private let updater: SPUUpdater
    private var cancellables = Set<AnyCancellable>()

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates

        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        
        $automaticallyChecksForUpdates
            .dropFirst()
            .sink { [weak self] checksAutomatically in
                self?.updater.automaticallyChecksForUpdates = checksAutomatically
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, SPUUpdaterDelegate, NSMenuDelegate {

    var mainWindow: NSWindow?
    var statusItem: NSStatusItem?
    var cheatsheetWindow: NSWindow?
    var assigningOverlayWindow: NSWindow?

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

    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        UserDefaults.standard.register(defaults: ["SUEnableAutomaticChecks": true])

        settings.setupAppearanceMonitoring()
        UNUserNotificationCenter.current().delegate = self
        
        NotificationManager.shared.requestUserPermission { granted in
            print("User notification permissions granted: \(granted)")
        }
        
        if updaterViewModel.automaticallyChecksForUpdates {
            updaterController.updater.checkForUpdatesInBackground()
        }

        let shouldShowWindow = !settings.hasCompletedOnboarding ||
                                CommandLine.arguments.contains("--show-window-on-launch") ||
                                !hotKeyManager.hasAccessibilityPermissions ||
                                (!hotKeyManager.hasScreenRecordingPermissions && !settings.hasSkippedScreenRecordingPermission)

        if shouldShowWindow {
            handleOpenMainWindow()
        } else {
            NSApp.setActivationPolicy(.accessory)
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenMainWindow), name: .openMainWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutActivation), name: .shortcutActivated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRestartRequest), name: .requestAppRestart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePermissionsRevoked), name: .permissionsRevoked, object: nil)
        
        NotificationCenter.default.addObserver(forName: .showCheatsheet, object: nil, queue: .main) { [weak self] _ in self?.showCheatsheet() }
        NotificationCenter.default.addObserver(forName: .hideCheatsheet, object: nil, queue: .main) { [weak self] _ in self?.hideCheatsheet() }
        NotificationCenter.default.addObserver(forName: .showAssigningOverlay, object: nil, queue: .main) { [weak self] _ in self?.showAssigningOverlay() }
        NotificationCenter.default.addObserver(forName: .hideAssigningOverlay, object: nil, queue: .main) { [weak self] _ in self?.hideAssigningOverlay() }
        NotificationCenter.default.addObserver(forName: .cheatsheetKeyDown, object: nil, queue: .main) { [weak self] _ in self?.handleCheatsheetKeyDown() }
        NotificationCenter.default.addObserver(forName: .cheatsheetKeyUp, object: nil, queue: .main) { [weak self] _ in self?.handleCheatsheetKeyUp() }
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
    
    @objc private func handlePermissionsRevoked() {
        NotificationManager.shared.sendNotification(
            title: "WarpKey Permissions Needed",
            body: "A required permission was revoked. Please re-enable it to restore full functionality."
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.handleOpenMainWindow()
        }
    }

    @objc func handleOpenMainWindow() {
        if mainWindow == nil {
            class KeyWindow: NSWindow {
                override var canBecomeKey: Bool { return true }
            }

            let window = KeyWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            window.center()
            window.title = "WarpKey"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.isOpaque = true
            
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
    
    @objc func showPreferences(_ sender: Any?) {
        handleOpenMainWindow()
        NotificationCenter.default.post(name: .goToSettingsPageInMainWindow, object: nil)
    }
    
    @objc func handleRestartRequest() {
        guard let appPath = Bundle.main.bundlePath as String? else { return }
        
        let pid = ProcessInfo.processInfo.processIdentifier
        let command = "(while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open -a \"\(appPath)\" --args --show-window-on-launch) &"
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        
        do {
            try task.run()
            NSApp.terminate(self)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Relaunch Required"
            alert.informativeText = "WarpKey needs to be relaunched to use the new permissions, but the automatic restart failed. Please quit and open the app again manually."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func createStatusItem() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.wantsLayer = true
            let icon = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "WarpKey")
            icon?.isTemplate = true
            button.image = icon
            button.toolTip = "WarpKey"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        statusItem?.isVisible = true
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        menu.addItem(withTitle: "Open WarpKey", action: #selector(handleOpenMainWindow), keyEquivalent: "o")
        menu.addItem(.separator())
        
        let allAssignments = settings.currentProfile.wrappedValue.assignments
        if allAssignments.isEmpty {
            let noShortcutsItem = NSMenuItem(title: "No shortcuts configured.", action: nil, keyEquivalent: "")
            noShortcutsItem.isEnabled = false
            menu.addItem(noShortcutsItem)
        } else {
            for (index, assignment) in allAssignments.sorted(by: { $0.configuration.target.displayName < $1.configuration.target.displayName }).enumerated() {
                let keyEquivalent = (index < 9) ? "\(index + 1)" : ""
                let title = assignment.configuration.target.displayName
                let menuItem = NSMenuItem(title: title, action: #selector(menuItemTriggered(_:)), keyEquivalent: keyEquivalent)
                menuItem.representedObject = assignment
                menuItem.image = assignment.configuration.target.getIcon(using: hotKeyManager)
                menu.addItem(menuItem)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit WarpKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func menuItemTriggered(_ sender: NSMenuItem) {
        guard let assignment = sender.representedObject as? Assignment else { return }
        _ = hotKeyManager.handleActivation(assignment: assignment)
    }

    @objc func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window === mainWindow {
                NSApp.setActivationPolicy(.accessory)
            } else if window === assigningOverlayWindow {
                assigningOverlayWindow = nil
                hotKeyManager.cancelRecording()
            }
        }
    }
        
    @objc private func handleShortcutActivation() {
        guard let button = statusItem?.button else { return }

        if let filter = CIFilter(name: "CIColorInvert") {
            button.layer?.filters = [filter]
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            button.layer?.filters = nil
        }
    }
    
    @objc private func handleCheatsheetKeyDown() {
        guard let button = statusItem?.button else { return }
        if let filter = CIFilter(name: "CIColorInvert") {
            button.layer?.filters = [filter]
        }
    }

    @objc private func handleCheatsheetKeyUp() {
        guard let button = statusItem?.button else { return }
        button.layer?.filters = nil
    }

    @objc private func handleAppDidBecomeActive() {
        hotKeyManager.restartMonitoringIfNeeded()
    }

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
        
        let cheatsheetSize = CGSize(width: screen.visibleFrame.width * 0.9, height: screen.visibleFrame.height * 0.8)
        window.setContentSize(cheatsheetSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func hideCheatsheet() {
        cheatsheetWindow?.orderOut(nil)
        cheatsheetWindow = nil
    }

    func createAssigningOverlayWindow() {
        guard assigningOverlayWindow == nil else { return }
        
        let recordingView = ShortcutRecordingView(manager: hotKeyManager, isFloating: true)
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
        window.contentView = NSHostingView(rootView: recordingView)
        window.setContentSize(NSSize(width: 400, height: 250))
        
        window.isReleasedWhenClosed = true
        
        self.assigningOverlayWindow = window
    }
    
    func showAssigningOverlay() {
        if assigningOverlayWindow == nil {
            createAssigningOverlayWindow()
        }
        
        guard let window = assigningOverlayWindow, !window.isVisible, let screen = NSScreen.main else { return }
        
        let windowSize = window.frame.size
        let screenFrame = screen.visibleFrame
        let newOrigin = NSPoint(x: screenFrame.maxX - windowSize.width - 20, y: screenFrame.maxY - windowSize.height - 20)
        
        window.setFrameOrigin(newOrigin)
        
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        })
    }
    
    func hideAssigningOverlay() {
        guard let window = assigningOverlayWindow, window.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
        })
    }

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

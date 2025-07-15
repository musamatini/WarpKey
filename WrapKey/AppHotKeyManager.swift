// AppHotKeyManager.swift

import SwiftUI
import AppKit
import CoreGraphics

// --- Data model for each shortcut ---
struct ShortcutConfiguration: Codable, Hashable {
    var bundleId: String
    var behavior: Behavior = .activateOrHide

    // ✅ CHANGED: "Activate" is now "Hide/Unhide" for clarity.
    enum Behavior: String, Codable, CaseIterable, Hashable {
        case activateOrHide = "Hide/Unhide"
        case cycleWindows = "Cycle"
    }
}

enum ModifierKeyCode {
    static let rightCommand: CGKeyCode = 54
    static let leftCommand: CGKeyCode = 55
    static let rightOption: CGKeyCode = 61
    static let leftOption: CGKeyCode = 58
}

class AppHotKeyManager: ObservableObject {
    
    @Published var assignments: [CGKeyCode: ShortcutConfiguration] = [:]
    private var lastCycledWindowIndex: [pid_t: Int] = [:]
    private var isRightCommandDown = false
    private var isRightOptionDown = false
    private var activationWorkItem: DispatchWorkItem?
    private var eventTap: CFMachPort?
    private let assignmentsKey = "RCMD_AppAssignments_v3"

    init() {
        print("[DEBUG] AppHotKeyManager initializing...")
        loadAssignments()
        
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            self.stopMonitoring()
        }
        
        startMonitoring()
    }
    
    deinit {
        print("[DEBUG] AppHotKeyManager deinitializing...")
        stopMonitoring()
    }

    private func startMonitoring() {
        if !AccessibilityManager.checkPermissions() {
            print("[WARN] Accessibility permissions not granted. App may not function correctly.")
        }
        let eventTapCallback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            if let manager = refcon.map({ Unmanaged<AppHotKeyManager>.fromOpaque($0).takeUnretainedValue() }) {
                return manager.handle(proxy: proxy, type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }
        let selfAsUnsafeMutableRawPointer = Unmanaged.passUnretained(self).toOpaque()
        let eventsToMonitor: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: eventsToMonitor, callback: eventTapCallback, userInfo: selfAsUnsafeMutableRawPointer)
        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            print("[FATAL ERROR] Failed to create CGEventTap. INPUT MONITORING PERMISSION ISSUE.")
        }
    }
    
    private func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }
    
    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .flagsChanged:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            handleModifierKey(keyCode: keyCode, flags: event.flags)
        case .keyDown:
            if isRightCommandDown {
                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                if isRightOptionDown {
                    assign(keyCode: keyCode)
                    return nil
                } else {
                    if handleActivation(keyCode: keyCode) {
                        return nil
                    }
                }
            }
        default: break
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleModifierKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        switch keyCode {
        case ModifierKeyCode.rightCommand: isRightCommandDown = flags.contains(.maskCommand)
        case ModifierKeyCode.rightOption: isRightOptionDown = flags.contains(.maskAlternate)
        default: break
        }
    }
    
    private func assign(keyCode: CGKeyCode) {
        DispatchQueue.main.async {
            guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
                  let bundleId = frontmostApp.bundleIdentifier else { return }
            if bundleId == Bundle.main.bundleIdentifier { return }
            
            self.assignments[keyCode] = ShortcutConfiguration(bundleId: bundleId)
            self.saveAssignments()
            
            let appName = self.getAppName(for: bundleId) ?? "The App"
            let keyStr = self.keyString(for: keyCode)
            NotificationManager.shared.sendAssignmentNotification(appName: appName, keyString: keyStr)
            print("[ACTION] Assigned \(appName) to key \(keyStr).")
        }
    }

    private func handleActivation(keyCode: CGKeyCode) -> Bool {
        guard let config = assignments[keyCode] else {
            return false
        }
        
        activationWorkItem?.cancel()

        let newWorkItem = DispatchWorkItem {
            guard let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: config.bundleId).first else {
                print("[ACTION] App \(config.bundleId) not running. Launching.")
                self.launchAndActivate(bundleId: config.bundleId)
                return
            }
            
            switch config.behavior {
            case .activateOrHide:
                self.activateOrHide(app: targetApp)
            case .cycleWindows:
                self.cycleWindows(for: targetApp)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: newWorkItem)
        self.activationWorkItem = newWorkItem
        return true
    }

    private func activateOrHide(app: NSRunningApplication) {
        if app.isActive {
            print("[ACTION] App \(app.bundleIdentifier ?? "") is frontmost. Hiding.")
            app.hide()
        } else {
            print("[ACTION] App \(app.bundleIdentifier ?? "") is not frontmost. Activating.")
            forceActivate(app: app)
        }
    }
    
    private func cycleWindows(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        print("[ACTION] Cycling windows for \(app.bundleIdentifier ?? "") (PID: \(pid))")

        if !app.isActive {
            app.unhide()
            app.activate(options: .activateAllWindows)
        }

        let appElement = AXUIElementCreateApplication(pid)

        var allWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &allWindows) == .success,
              let windowList = allWindows as? [AXUIElement], !windowList.isEmpty else {
            print("[CYCLE] No windows found or accessible. Activating instead.")
            forceActivate(app: app)
            return
        }

        let cycleableWindows = windowList.filter { window in
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            if let subrole = subrole as? String, subrole == kAXStandardWindowSubrole as String {
                var isMinimized: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized)
                return (isMinimized as? NSNumber)?.boolValue == false
            }
            return false
        }

        let sortedWindows = cycleableWindows.sorted { w1, w2 -> Bool in
            var title1: CFTypeRef?, title2: CFTypeRef?
            AXUIElementCopyAttributeValue(w1, kAXTitleAttribute as CFString, &title1)
            AXUIElementCopyAttributeValue(w2, kAXTitleAttribute as CFString, &title2)
            return (title1 as? String ?? "") < (title2 as? String ?? "")
        }

        guard !sortedWindows.isEmpty else {
            print("[CYCLE] No standard, non-minimized windows found. Activating instead.")
            forceActivate(app: app)
            return
        }

        print("[CYCLE] Found \(sortedWindows.count) windows, sorted by title.")

        let lastIndex = self.lastCycledWindowIndex[pid]

        let nextIndex: Int
        if let lastIndex = lastIndex, lastIndex < sortedWindows.count {
            print("[CYCLE] Found last-used index for PID \(pid): \(lastIndex).")
            nextIndex = (lastIndex + 1) % sortedWindows.count
        } else {
            print("[CYCLE] No valid index found for PID \(pid). Starting from 0.")
            nextIndex = 0
        }
        
        print("[CYCLE] Next window index is \(nextIndex).")
        let nextWindow = sortedWindows[nextIndex]
        AXUIElementPerformAction(nextWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, nextWindow)
        self.lastCycledWindowIndex[pid] = nextIndex
    }
    
    private func launchAndActivate(bundleId: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { runningApp, _ in
            if let runningApp = runningApp {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.forceActivate(app: runningApp)
                }
            }
        }
    }
    
    private func forceActivate(app: NSRunningApplication) {
        app.unhide()
        app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    }

    func removeAssignment(keyCode: CGKeyCode) {
        DispatchQueue.main.async {
            self.assignments.removeValue(forKey: keyCode)
            self.saveAssignments()
        }
    }
    
    func clearAllAssignments() {
        DispatchQueue.main.async {
            self.assignments.removeAll()
            self.saveAssignments()
        }
    }

    func updateBehavior(for keyCode: CGKeyCode, to newBehavior: ShortcutConfiguration.Behavior) {
        DispatchQueue.main.async {
            guard self.assignments[keyCode] != nil else { return }
            self.assignments[keyCode]?.behavior = newBehavior
            self.saveAssignments()
            print("[ACTION] Updated behavior for key \(keyCode) to \(newBehavior.rawValue)")
        }
    }

    private func saveAssignments() {
        do {
            let data = try JSONEncoder().encode(assignments)
            UserDefaults.standard.set(data, forKey: assignmentsKey)
        } catch {
            print("[ERROR] Failed to save assignments: \(error.localizedDescription)")
        }
    }
    
    private func loadAssignments() {
        guard let data = UserDefaults.standard.data(forKey: assignmentsKey) else { return }
        do {
            assignments = try JSONDecoder().decode([CGKeyCode: ShortcutConfiguration].self, from: data)
        } catch {
            print("[ERROR] Failed to load assignments, data might be outdated. Clearing. Error: \(error.localizedDescription)")
            UserDefaults.standard.removeObject(forKey: assignmentsKey)
        }
    }
    
    func getAppName(for bundleId: String) -> String? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleId
    }
    
    func getAppIcon(for bundleId: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
    
    func keyString(for keyCode: CGKeyCode) -> String {
        let keyMap: [CGKeyCode: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K"]
        return keyMap[keyCode] ?? "Key \(keyCode)"
    }
}

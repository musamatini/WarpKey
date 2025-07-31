//AppHotkeyManager.swift
import SwiftUI
import AppKit
import CoreGraphics
import Combine

// MARK: - Shortcut Target Definitions
enum ShortcutTarget: Codable, Hashable {
    case app(bundleId: String)
    case url(String)
    case file(String)
    case script(command: String, runsInTerminal: Bool)
    case shortcut(name: String)
    
    var category: ShortcutCategory {
        switch self {
        case .app: .app
        case .url: .url
        case .file: .file
        case .script: .script
        case .shortcut: .shortcut
        }
    }
}

struct ShortcutConfiguration: Codable, Hashable {
    var target: ShortcutTarget
    var behavior: Behavior = .activateOrHide

    enum Behavior: String, Codable, CaseIterable, Hashable {
        case activateOrHide = "Hide/Unhide"
        case cycleWindows = "Cycle"
    }
}

// MARK: - Modifier Key Definition
struct ModifierKey: Codable, Equatable, Hashable, Identifiable {
    var id: CGKeyCode { keyCode }
    let keyCode: CGKeyCode
    let displayName: String
    let isTrueModifier: Bool

    var flagMask: CGEventFlags {
        guard isTrueModifier else { return [] }
        switch keyCode {
        case 55, 54: return .maskCommand
        case 58, 61: return .maskAlternate
        case 56, 60: return .maskShift
        case 59, 62: return .maskControl
        case 63: return .maskSecondaryFn
        default: return []
        }
    }
    
    var symbol: String {
        if displayName.lowercased().contains("command") { return "⌘" }
        if displayName.lowercased().contains("option") { return "⌥" }
        if displayName.lowercased().contains("shift") { return "⇧" }
        if displayName.lowercased().contains("control") { return "⌃" }
        if displayName.lowercased().contains("function") { return "fn" }
        return displayName
    }
    
    private init(keyCode: CGKeyCode, displayName: String, isTrueModifier: Bool) {
        self.keyCode = keyCode
        self.displayName = displayName
        self.isTrueModifier = isTrueModifier
    }
    
    static func from(keyCode: CGKeyCode) -> ModifierKey {
        let trueModifierDisplayNames: [CGKeyCode: String] = [
            55: "Left Command", 54: "Right Command",
            58: "Left Option", 61: "Right Option",
            56: "Left Shift", 60: "Right Shift",
            59: "Left Control", 62: "Right Control",
            63: "Function (fn)"
        ]
        
        if let displayName = trueModifierDisplayNames[keyCode] {
            return ModifierKey(keyCode: keyCode, displayName: displayName, isTrueModifier: true)
        } else {
            let displayName = KeyboardLayout.character(for: keyCode) ?? "Key \(keyCode)"
            return ModifierKey(keyCode: keyCode, displayName: displayName, isTrueModifier: false)
        }
    }
}

// MARK: - HotKey Manager
class AppHotKeyManager: ObservableObject {
    // MARK: - Published Properties
    @Published var hasAccessibilityPermissions: Bool
    @Published var isListeningForNewModifier: Bool = false
    @Published var modifierToChange: (category: ShortcutCategory, type: ModifierType)? = nil
    @Published var isListeningForAssignment = false
    @Published var conflictingAssignmentIDs: Set<UUID> = []

    // MARK: - Private Properties
    private var targetForAssignment: ShortcutTarget?
    private var assignmentIDForReassignment: UUID?
    private var pressedModifierKeys = Set<CGKeyCode>()
    private var pressedNonModifierKeys = Set<CGKeyCode>()
    private let modifierKeyToFlagMap: [CGKeyCode: CGEventFlags] = [
        55: .maskCommand, 54: .maskCommand,
        58: .maskAlternate, 61: .maskAlternate,
        56: .maskShift, 60: .maskShift,
        59: .maskControl, 62: .maskControl,
        63: .maskSecondaryFn
    ]
    private var lastCycledWindowIndex: [pid_t: Int] = [:]
    private var eventTap: CFMachPort?
    private var isMonitoringActive = false
    private var settingsCancellable: AnyCancellable?
    private var previousConflictingAssignmentIDs: Set<UUID> = []
    var settings: SettingsManager

    // MARK: - Initialization
    init(settings: SettingsManager) {
        self.settings = settings
        self.hasAccessibilityPermissions = AccessibilityManager.checkPermissions()
        
        settingsCancellable = settings.$profiles
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkForConflicts()
                self?.restartMonitoring()
            }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in self.stopMonitoring() }
        startMonitoring()
        checkForConflicts()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Event Monitoring
    func restartMonitoringIfNeeded() {
        let hadPermissions = hasAccessibilityPermissions
        let nowHasPermissions = AccessibilityManager.checkPermissions()
        
        if nowHasPermissions && !hadPermissions {
            NotificationCenter.default.post(name: .requestAppRestart, object: nil)
            return
        }

        self.hasAccessibilityPermissions = nowHasPermissions
        
        guard !isMonitoringActive, hasAccessibilityPermissions else { return }
        
        DispatchQueue.main.async {
            self.restartMonitoring()
        }
    }
    
    private func restartMonitoring() {
        stopMonitoring()
        startMonitoring()
    }

    private func startMonitoring() {
        if isMonitoringActive { return }
        
        guard hasAccessibilityPermissions else {
            print("[WARN] Accessibility permissions not granted. Key monitoring is disabled.")
            isMonitoringActive = false
            return
        }
        
        let eventTapCallback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard let manager = refcon.map({ Unmanaged<AppHotKeyManager>.fromOpaque($0).takeUnretainedValue() }) else { return Unmanaged.passUnretained(event) }
            return manager.handle(proxy: proxy, type: type, event: event)
        }
        let selfAsUnsafeMutableRawPointer = Unmanaged.passUnretained(self).toOpaque()
        let eventsToMonitor: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: eventsToMonitor, callback: eventTapCallback, userInfo: selfAsUnsafeMutableRawPointer)
        
        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isMonitoringActive = true
            print("[INFO] Event tap created and monitoring started.")
        } else {
            isMonitoringActive = false
            print("[FATAL ERROR] Failed to create CGEventTap. INPUT MONITORING PERMISSION ISSUE.")
        }
    }
    
    private func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
            isMonitoringActive = false
            print("[INFO] Event tap stopped.")
        }
    }
    
    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if isListeningForNewModifier {
            if type == .keyDown || type == .flagsChanged { NotificationCenter.default.post(name: .keyPressEvent, object: event); return nil }
            return nil
        }
        
        if isListeningForAssignment {
            if type == .keyDown { completeAssignment(event: event); return nil }
            return nil
        }
        
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        
        switch type {
        case .flagsChanged:
            if let flag = modifierKeyToFlagMap[keyCode] {
                if event.flags.contains(flag) { pressedModifierKeys.insert(keyCode) }
                else { pressedModifierKeys.remove(keyCode) }
            }
        case .keyDown: pressedNonModifierKeys.insert(keyCode)
        case .keyUp: pressedNonModifierKeys.remove(keyCode)
        default: break
        }
        
        let allTriggerKeys = Set(settings.currentProfile.wrappedValue.triggerModifiers.values.flatMap { $0 })
        let secondaryKeys = Set(settings.currentProfile.wrappedValue.secondaryModifier)
        if allTriggerKeys.contains(where: { !$0.isTrueModifier && $0.keyCode == keyCode }) { return nil }
        if secondaryKeys.contains(where: { !$0.isTrueModifier && $0.keyCode == keyCode }) { return nil }
        
        if type == .keyDown {
            if isSecondaryPressed() && isTriggerPressed(for: .app) {
                assignAppShortcut(keyCode: keyCode)
                return nil
            }
            
            var activated = false
            let assignmentsForKeyCode = settings.currentProfile.wrappedValue.assignments.filter { $0.keyCode == keyCode }
            
            for assignment in assignmentsForKeyCode {
                if isTriggerPressed(for: assignment.configuration.target.category) {
                    _ = handleActivation(assignment: assignment)
                    activated = true
                }
            }
            
            if activated {
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - State Checkers
    private func areKeysPressed(triggerKeys keys: [ModifierKey]) -> Bool {
        if keys.isEmpty { return false }
        
        let requiredTrueModifiers = Set(keys.filter { $0.isTrueModifier }.map { $0.keyCode })
        let requiredNonModifiers = Set(keys.filter { !$0.isTrueModifier }.map { $0.keyCode })

        if !pressedNonModifierKeys.isSuperset(of: requiredNonModifiers) {
            return false
        }
        
        let allHeldTrueModifiers = pressedModifierKeys.intersection(Set(modifierKeyToFlagMap.keys))
        return allHeldTrueModifiers == requiredTrueModifiers
    }
    
    private func isTriggerPressed(for category: ShortcutCategory) -> Bool {
        guard let triggers = settings.currentProfile.wrappedValue.triggerModifiers[category] else { return false }
        return areKeysPressed(triggerKeys: triggers)
    }
    
    private func isSecondaryPressed() -> Bool {
        let secondaryKeys = settings.currentProfile.wrappedValue.secondaryModifier
        return areKeysPressed(triggerKeys: secondaryKeys)
    }

    // MARK: - Modifier & Assignment Logic
    func listenForNewAssignment(target: ShortcutTarget, assignmentID: UUID? = nil) {
        pressedModifierKeys.removeAll()
        pressedNonModifierKeys.removeAll()
        targetForAssignment = target
        assignmentIDForReassignment = assignmentID
        isListeningForAssignment = true
    }
    
    private func completeAssignment(event: CGEvent) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        
        let allTriggerKeyCodes = settings.currentProfile.wrappedValue.triggerModifiers.values.flatMap { $0 }.map { $0.keyCode }
        let secondaryKeyCodes = settings.currentProfile.wrappedValue.secondaryModifier.map { $0.keyCode }
        
        if allTriggerKeyCodes.contains(keyCode) || secondaryKeyCodes.contains(keyCode) {
            NotificationManager.shared.sendNotification(title: "Invalid Key", body: "You cannot assign a modifier key as a shortcut.")
            isListeningForAssignment = false; return
        }

        guard let target = targetForAssignment else { isListeningForAssignment = false; return }
        
        if let assignmentID = assignmentIDForReassignment {
            settings.updateAssignment(id: assignmentID, newKeyCode: keyCode)
        } else {
            let newAssignment = Assignment(keyCode: keyCode, configuration: ShortcutConfiguration(target: target))
            settings.addAssignment(newAssignment)
        }
        
        let newTriggerText = modifierKeyCombinationString(for: settings.triggerModifiers(for: target))
        NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "\(newTriggerText) + \(keyString(for: keyCode)) is ready.")
        isListeningForAssignment = false
        targetForAssignment = nil
        assignmentIDForReassignment = nil
    }

    private func assignAppShortcut(keyCode: CGKeyCode) {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier,
              bundleId != Bundle.main.bundleIdentifier else { return }
        
        let target = ShortcutTarget.app(bundleId: bundleId)
        
        let newAssignment = Assignment(keyCode: keyCode, configuration: ShortcutConfiguration(target: target))
        settings.addAssignment(newAssignment)
        let appName = getAppName(for: bundleId) ?? "The App"
        NotificationManager.shared.sendAssignmentNotification(appName: appName, keyString: keyString(for: keyCode))
    }
    
    private func checkForConflicts() {
        var hotkeys: [String: [UUID]] = [:]
        for assignment in settings.currentProfile.wrappedValue.assignments {
            let triggers = settings.triggerModifiers(for: assignment.configuration.target)
            let sortedTriggerKeyCodes = triggers.map { $0.keyCode }.sorted()
            let hotkeyID = "\(sortedTriggerKeyCodes)-\(assignment.keyCode)"
            hotkeys[hotkeyID, default: []].append(assignment.id)
        }
        
        let currentConflicts = hotkeys.values.filter { $0.count > 1 }.flatMap { $0 }
        self.conflictingAssignmentIDs = Set(currentConflicts)

        let newlyConflictingIDs = self.conflictingAssignmentIDs.subtracting(previousConflictingAssignmentIDs)

        if !newlyConflictingIDs.isEmpty {
            let allAssignments = settings.currentProfile.wrappedValue.assignments
            var conflictingHotkeys: [String: [String]] = [:]

            for id in newlyConflictingIDs {
                guard let assignment = allAssignments.first(where: { $0.id == id }) else { continue }

                let triggers = settings.triggerModifiers(for: assignment.configuration.target)
                let key = keyString(for: assignment.keyCode)
                let hotkeyString = "\(modifierKeyCombinationString(for: triggers)) + \(key)"
                let assignmentName = getDisplayName(for: assignment.configuration.target) ?? "Unnamed Shortcut"

                conflictingHotkeys[hotkeyString, default: []].append(assignmentName)
            }

            for (hotkey, names) in conflictingHotkeys {
                if names.count > 1 {
                    let body = "Hotkey \(hotkey) is now used for: \(names.joined(separator: ", "))."
                    NotificationManager.shared.sendNotification(title: "Shortcut Conflict Detected", body: body)
                }
            }
        }
        
        self.previousConflictingAssignmentIDs = self.conflictingAssignmentIDs
    }

    // MARK: - Shortcut Activation
    private func handleActivation(assignment: Assignment) -> Bool {
        let config = assignment.configuration
        let workItem = DispatchWorkItem {
            NotificationCenter.default.post(name: .shortcutActivated, object: nil)
            switch config.target {
            case .app(let bundleId): self.handleAppActivation(bundleId: bundleId, behavior: config.behavior)
            case .url(let urlString): if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
            case .file(let path): NSWorkspace.shared.open(URL(fileURLWithPath: path))
            case .script(let command, let runsInTerminal): self.runScript(command: command, runsInTerminal: runsInTerminal)
            case .shortcut(let name): self.runShortcut(name: name)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        return true
    }
    
    private func handleAppActivation(bundleId: String, behavior: ShortcutConfiguration.Behavior) {
        guard let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            launchAndActivate(bundleId: bundleId)
            return
        }
        switch behavior {
        case .activateOrHide: activateOrHide(app: targetApp)
        case .cycleWindows: cycleWindows(for: targetApp)
        }
    }
    
    private func activateOrHide(app: NSRunningApplication) {
        if app.isActive {
            app.hide()
        } else {
            app.unhide()
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
    }
    
    private func cycleWindows(for app: NSRunningApplication) {
        if !app.isActive { app.unhide(); app.activate(options: .activateAllWindows) }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var allWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &allWindows) == .success,
              let windowList = allWindows as? [AXUIElement], !windowList.isEmpty else {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            return
        }
        
        let cycleableWindows = windowList.filter { window in
            var subrole: CFTypeRef?; AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            if let subrole = subrole as? String, subrole == kAXStandardWindowSubrole as String {
                var isMinimized: CFTypeRef?; AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized)
                return (isMinimized as? NSNumber)?.boolValue == false
            }
            return false
        }
        
        guard !cycleableWindows.isEmpty else {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            return
        }
        
        let sortedWindows = cycleableWindows.sorted { w1, w2 -> Bool in
            var t1: CFTypeRef?, t2: CFTypeRef?
            AXUIElementCopyAttributeValue(w1, kAXTitleAttribute as CFString, &t1)
            AXUIElementCopyAttributeValue(w2, kAXTitleAttribute as CFString, &t2)
            return (t1 as? String ?? "") < (t2 as? String ?? "")
        }
        
        let lastIndex = self.lastCycledWindowIndex[app.processIdentifier]
        let nextIndex = (lastIndex != nil && lastIndex! < sortedWindows.count) ? (lastIndex! + 1) % sortedWindows.count : 0
        let nextWindow = sortedWindows[nextIndex]
        
        AXUIElementPerformAction(nextWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, nextWindow)
        self.lastCycledWindowIndex[app.processIdentifier] = nextIndex
    }
    
    private func launchAndActivate(bundleId: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, _ in
            app?.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
    }
    
    private func runScript(command: String, runsInTerminal: Bool) {
        if runsInTerminal {
            let escapedCommand = command.replacingOccurrences(of: "\"", with: "\\\"")
            let appleScript = """
            tell application "Terminal"
                activate
                do script "\(escapedCommand)" in window 1
            end tell
            """
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", appleScript]
            do { try task.run() } catch { print("Failed to run script in Terminal: \(error)") }
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", command]
            do { try task.run() } catch { print("Failed to run script in background: \(error)") }
        }
    }
    
    private func runShortcut(name: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", name]
        do {
            try task.run()
        } catch {
            print("Failed to run shortcut '\(name)': \(error)")
            NotificationManager.shared.sendNotification(title: "Shortcut Failed", body: "Could not run '\(name)'. Check the name and Shortcut permissions.")
        }
    }
    
    // MARK: - Helpers
    private func getDisplayName(for target: ShortcutTarget) -> String? {
        switch target {
        case .app(let bundleId):
            return getAppName(for: bundleId)
        case .url(let urlString):
            return URL(string: urlString)?.host ?? "URL"
        case .file(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        case .script:
            return "Script"
        case .shortcut(let name):
            return name
        }
    }
    
    func getAppName(for bundleId: String) -> String? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleId
    }
    
    func getAppIcon(for bundleId: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
    
    func keyString(for keyCode: CGKeyCode) -> String {
        return KeyboardLayout.character(for: keyCode) ?? "Key \(keyCode)"
    }
    
    func modifierKeyCombinationString(for keys: [ModifierKey]) -> String {
        if keys.isEmpty { return "???" }
        return keys.map { $0.symbol }.joined(separator: " + ")
    }
}

//AppHotkeyManager.swift
import SwiftUI
import AppKit
import CoreGraphics
import Combine
import Carbon.HIToolbox
import ApplicationServices

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

// MARK: - Shortcut Key Definition
struct ShortcutKey: Codable, Equatable, Hashable, Identifiable {
    var id: CGKeyCode { keyCode }
    let keyCode: CGKeyCode
    let displayName: String
    let isModifier: Bool

    var flag: CGEventFlags? {
        guard isModifier else { return nil }
        switch keyCode {
        case 55, 54: return .maskCommand
        case 58, 61: return .maskAlternate
        case 56, 60: return .maskShift
        case 59, 62: return .maskControl
        case 63: return .maskSecondaryFn
        default: return nil
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
    
    static func from(event: CGEvent) -> ShortcutKey {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isModifier = event.type == .flagsChanged
        return self.from(keyCode: keyCode, isModifier: isModifier)
    }

    static func from(keyCode: CGKeyCode, isModifier: Bool) -> ShortcutKey {
        let displayName: String
        if isModifier {
            let names: [CGKeyCode: String] = [
                55: "Command", 54: "Command", 58: "Option", 61: "Option",
                56: "Shift", 60: "Shift", 59: "Control", 62: "Control", 63: "Function"
            ]
            displayName = names[keyCode] ?? "Mod \(keyCode)"
        } else {
            displayName = KeyboardLayout.character(for: keyCode) ?? "Key \(keyCode)"
        }
        return ShortcutKey(keyCode: keyCode, displayName: displayName, isModifier: isModifier)
    }
}

enum RecordingMode {
    case create(target: ShortcutTarget)
    case edit(assignmentID: UUID, target: ShortcutTarget)
}

// MARK: - HotKey Manager
class AppHotKeyManager: ObservableObject {
    // MARK: - Published Properties
    @Published var hasAccessibilityPermissions: Bool
    @Published var recordingState: RecordingMode? = nil
    @Published var recordedKeys: [ShortcutKey] = []
    @Published var conflictingAssignmentIDs: Set<UUID> = []

    // MARK: - Private Properties
    private var activeKeys = Set<CGKeyCode>()
    private var lastKeyDown: CGKeyCode?
    private var lastCycledWindowIndex: [pid_t: Int] = [:]
    private var eventTap: CFMachPort?
    private var isMonitoringActive = false
    private var settingsCancellable: AnyCancellable?
    private var previousConflictingAssignmentIDs: Set<UUID> = []
    private var isRecordingSessionActive = true
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
        hasAccessibilityPermissions = AccessibilityManager.checkPermissions()
        
        if hasAccessibilityPermissions && !hadPermissions {
            NotificationCenter.default.post(name: .requestAppRestart, object: nil)
            return
        }
        
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
            isMonitoringActive = false
            return
        }
        
        let eventTapCallback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard let manager = refcon.map({ Unmanaged<AppHotKeyManager>.fromOpaque($0).takeUnretainedValue() }) else { return Unmanaged.passUnretained(event) }
            return manager.handle(proxy: proxy, type: type, event: event)
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let events: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: events, callback: eventTapCallback, userInfo: selfPtr)
        
        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isMonitoringActive = true
        } else {
            isMonitoringActive = false
            hasAccessibilityPermissions = false
        }
    }
    
    private func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
            isMonitoringActive = false
        }
    }
    
    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Update activeKeys before any other logic
        switch type {
        case .flagsChanged:
            let flags = event.flags
            if [55, 54].contains(keyCode) { if flags.contains(.maskCommand) { activeKeys.insert(keyCode) } else { activeKeys.remove(keyCode) } }
            else if [58, 61].contains(keyCode) { if flags.contains(.maskAlternate) { activeKeys.insert(keyCode) } else { activeKeys.remove(keyCode) } }
            else if [56, 60].contains(keyCode) { if flags.contains(.maskShift) { activeKeys.insert(keyCode) } else { activeKeys.remove(keyCode) } }
            else if [59, 62].contains(keyCode) { if flags.contains(.maskControl) { activeKeys.insert(keyCode) } else { activeKeys.remove(keyCode) } }
            else if keyCode == 63 { if flags.contains(.maskSecondaryFn) { activeKeys.insert(keyCode) } else { activeKeys.remove(keyCode) } }
        case .keyDown:
            activeKeys.insert(keyCode)
            lastKeyDown = keyCode
        case .keyUp:
            activeKeys.remove(keyCode)
            if activeKeys.isEmpty { lastKeyDown = nil }
        default: break
        }

        if recordingState != nil {
            handleRecording()
            return nil // Consume event only when recording UI is active
        }
        
        if type == .keyDown {
            for assignment in settings.currentProfile.wrappedValue.assignments where !assignment.shortcut.isEmpty {
                let shortcutKeyCodes = Set(assignment.shortcut.map { $0.keyCode })
                
                if shortcutKeyCodes == activeKeys {
                    let nonModifierKeyInShortcut = assignment.shortcut.first(where: { !$0.isModifier })?.keyCode
                    if keyCode == nonModifierKeyInShortcut || (nonModifierKeyInShortcut == nil && lastKeyDown == keyCode) {
                        if handleActivation(assignment: assignment) {
                            return nil
                        }
                    }
                }
            }
        }
        
        return Unmanaged.passUnretained(event)
    }

    // MARK - Shortcut Recording
    func startRecording(for mode: RecordingMode) {
        DispatchQueue.main.async {
            self.recordedKeys = []
            self.recordingState = mode
            self.isRecordingSessionActive = true
        }
    }
    
    private func closeRecorder() {
        recordingState = nil
        recordedKeys = []
        isRecordingSessionActive = true
    }

    func cancelRecording() {
        closeRecorder()
    }
    
    private func isModifierKeyCode(_ keyCode: CGKeyCode) -> Bool {
        switch keyCode {
        case 54, 55, 56, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }

    private func handleRecording() {
        if isRecordingSessionActive && !activeKeys.isEmpty {
            // This is the first key press of a new combo.
            isRecordingSessionActive = false
            // Clear the visually latched keys from the last combo.
            DispatchQueue.main.async { self.recordedKeys = [] }
        }
        
        if !isRecordingSessionActive {
            // We are in the middle of a combo.
            // Only update the 'recordedKeys' if the number of active keys is greater than or equal to what's currently displayed.
            // This ensures we capture the "peak" of the combination and don't shrink it on key release.
            if activeKeys.count >= recordedKeys.count {
                DispatchQueue.main.async {
                    self.recordedKeys = self.activeKeys.map { aKeyCode in
                        return ShortcutKey.from(keyCode: aKeyCode, isModifier: self.isModifierKeyCode(aKeyCode))
                    }.sorted { $0.isModifier && !$1.isModifier }
                }
            }
            
            if activeKeys.isEmpty {
                // The combo has been fully released. Prepare for the next one.
                isRecordingSessionActive = true
            }
        }
    }
    
    func saveRecordedShortcut() {
        guard let state = recordingState else { return }
        
        let finalKeys = recordedKeys.sorted { $0.isModifier && !$1.isModifier }
        
        if finalKeys.isEmpty {
            closeRecorder()
            return
        }

        let displayName: String
        switch state {
        case .create(let target):
            let newAssignment = Assignment(id: UUID(), shortcut: finalKeys, configuration: .init(target: target))
            settings.addAssignment(newAssignment)
            displayName = getDisplayName(for: target) ?? "item"
        case .edit(let id, let target):
            settings.updateAssignment(id: id, newShortcut: finalKeys)
            displayName = getDisplayName(for: target) ?? "item"
        }
        
        let keyString = shortcutKeyCombinationString(for: finalKeys)
        NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "Shortcut for \(displayName) is now \(keyString).")
        
        closeRecorder()
    }
    
    func clearRecordedShortcut() {
        guard let state = recordingState else { return }

        switch state {
        case .create(let target):
            let newAssignment = Assignment(id: UUID(), shortcut: [], configuration: .init(target: target))
            settings.addAssignment(newAssignment)
            let displayName = getDisplayName(for: target) ?? "item"
            NotificationManager.shared.sendNotification(title: "Shortcut Added", body: "\(displayName) was added without a hotkey.")
            closeRecorder()

        case .edit(let id, let target):
            settings.updateAssignment(id: id, newShortcut: [])
            let displayName = getDisplayName(for: target) ?? "item"
            NotificationManager.shared.sendNotification(title: "Shortcut Cleared", body: "The hotkey for \(displayName) has been removed.")
            closeRecorder()
        }
    }
    
    private func checkForConflicts() {
        var hotkeys: [String: [UUID]] = [:]
        for assignment in settings.currentProfile.wrappedValue.assignments {
            if assignment.shortcut.isEmpty { continue }
            
            let sortedKeyCodes = assignment.shortcut.map { String($0.keyCode) }.sorted()
            let hotkeyID = sortedKeyCodes.joined(separator: "-")
            hotkeys[hotkeyID, default: []].append(assignment.id)
        }
        
        let currentConflicts = hotkeys.values.filter { $0.count > 1 }.flatMap { $0 }
        self.conflictingAssignmentIDs = Set(currentConflicts)

        let newlyConflictingIDs = self.conflictingAssignmentIDs.subtracting(previousConflictingAssignmentIDs)

        if !newlyConflictingIDs.isEmpty {
            // Logic to notify user about new conflicts can go here
        }
        self.previousConflictingAssignmentIDs = self.conflictingAssignmentIDs
    }

    // MARK: - Shortcut Activation
    func handleActivation(assignment: Assignment) -> Bool {
        let workItem = DispatchWorkItem {
            NotificationCenter.default.post(name: .shortcutActivated, object: nil)
            let config = assignment.configuration
            switch config.target {
            case .app(let bundleId): self.handleAppActivation(bundleId: bundleId, behavior: config.behavior)
            case .url(let urlString): if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
            case .file(let path): NSWorkspace.shared.open(URL(fileURLWithPath: path))
            case .script(let command, let runsInTerminal): self.runScript(command: command, runsInTerminal: runsInTerminal)
            case .shortcut(let name): self.runShortcut(name: name)
            }
        }
        DispatchQueue.main.async(execute: workItem)
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
        if app.isActive { app.hide() }
        else { app.unhide(); app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows]) }
    }
    

    private func cycleWindows(for app: NSRunningApplication) {
        if !app.isActive {
            app.unhide()
            app.activate(options: .activateAllWindows)
        }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var allWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &allWindows) == .success,
              let windowList = allWindows as? [AXUIElement], !windowList.isEmpty else {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
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
        
        guard !cycleableWindows.isEmpty else {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            return
        }
        
        let sortedWindows = cycleableWindows.sorted { w1, w2 in
            var pos1Ref, pos2Ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w1, kAXPositionAttribute as CFString, &pos1Ref) == .success,
                  AXUIElementCopyAttributeValue(w2, kAXPositionAttribute as CFString, &pos2Ref) == .success,
                  let pos1Val = pos1Ref, let pos2Val = pos2Ref else { return false }
            
            var point1 = CGPoint.zero, point2 = CGPoint.zero
            guard AXValueGetValue(pos1Val as! AXValue, .cgPoint, &point1),
                  AXValueGetValue(pos2Val as! AXValue, .cgPoint, &point2) else { return false }
            
            if point1.y != point2.y { return point1.y < point2.y }
            return point1.x < point2.x
        }
        
        let lastIndex = self.lastCycledWindowIndex[app.processIdentifier, default: -1]
        let nextIndex = (lastIndex + 1) % sortedWindows.count
        let nextWindow = sortedWindows[nextIndex]
        
        AXUIElementPerformAction(nextWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, nextWindow)
        app.activate(options: .activateIgnoringOtherApps)
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
            let appleScript = "tell application \"Terminal\" to do script \"\(command.replacingOccurrences(of: "\"", with: "\\\""))\""
            NSAppleScript(source: appleScript)?.executeAndReturnError(nil)
        } else {
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/zsh"); task.arguments = ["-c", command]
            do { try task.run() } catch { print("Failed to run script in background: \(error)") }
        }
    }
    
    private func runShortcut(name: String) {
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); task.arguments = ["run", name]
        do { try task.run() }
        catch { print("Failed to run shortcut '\(name)': \(error)"); NotificationManager.shared.sendNotification(title: "Shortcut Failed", body: "Could not run '\(name)'.") }
    }
    
    // MARK: - Helpers
    func getDisplayName(for target: ShortcutTarget) -> String? {
        switch target {
        case .app(let bundleId): return getAppName(for: bundleId)
        case .url(let urlString): return URL(string: urlString)?.host ?? "URL"
        case .file(let path): return URL(fileURLWithPath: path).lastPathComponent
        case .script: return "Script"
        case .shortcut(let name): return name
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
    
    func getIcon(for target: ShortcutTarget, size: NSSize = NSSize(width: 18, height: 18)) -> NSImage? {
        let image: NSImage?
        switch target {
        case .app(let bundleId): image = getAppIcon(for: bundleId)
        case .url: image = NSImage(systemSymbolName: "globe", accessibilityDescription: "URL")
        case .file: image = NSImage(systemSymbolName: "doc", accessibilityDescription: "File")
        case .script: image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Script")
        case .shortcut: image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Shortcut")
        }
        image?.size = size
        if target.category != .app { image?.isTemplate = true }
        return image
    }
    
    func shortcutKeyCombinationString(for keys: [ShortcutKey]) -> String {
        if keys.isEmpty { return "Not Set" }
        return keys.map { $0.symbol }.joined(separator: " + ")
    }
}

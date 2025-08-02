// AppHotKeyManager.swift

import SwiftUI
import AppKit
import CoreGraphics
import Combine
import Carbon.HIToolbox // For media key constants
import ApplicationServices

// --- Enums and Structs ---
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
    case cheatsheet
}

// --- Main Class ---
class AppHotKeyManager: ObservableObject {
    @Published var hasAccessibilityPermissions: Bool
    @Published var recordingState: RecordingMode? = nil
    @Published var recordedKeys: [ShortcutKey] = []
    @Published var conflictingAssignmentIDs: Set<UUID> = []
    @Published var isCheatsheetVisible: Bool = false

    private var isCheatsheetHotkeyActive = false
    private var activeKeys = Set<CGKeyCode>()
    private var lastKeyDown: CGKeyCode?
    private var lastCycledWindowIndex: [pid_t: Int] = [:]
    private var eventTap: CFMachPort?
    private var isMonitoringActive = false
    private var settingsCancellable: AnyCancellable?
    private var previousConflictingAssignmentIDs: Set<UUID> = []
    private var isRecordingSessionActive = true
    var settings: SettingsManager

    init(settings: SettingsManager) {
        self.settings = settings
        self.hasAccessibilityPermissions = AccessibilityManager.checkPermissions()

        settingsCancellable = settings.$profiles
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkForConflicts()
                self?.restartMonitoring()
            }
        
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopMonitoring()
        }
        
        startMonitoring()
        checkForConflicts()
    }

    deinit {
        stopMonitoring()
        settingsCancellable?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func restartMonitoringIfNeeded() {
        let hadPermissions = hasAccessibilityPermissions
        hasAccessibilityPermissions = AccessibilityManager.checkPermissions()

        if hasAccessibilityPermissions && !hadPermissions {
            NotificationCenter.default.post(name: .requestAppRestart, object: nil)
            return
        }
        guard !isMonitoringActive, hasAccessibilityPermissions else { return }
        DispatchQueue.main.async { self.restartMonitoring() }
    }

    private func restartMonitoring() {
        stopMonitoring()
        startMonitoring()
    }

    private func startMonitoring() {
        if isMonitoringActive { return }

        guard hasAccessibilityPermissions else {
            isMonitoringActive = false; return
        }

        let eventTapCallback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard let manager = refcon.map({ Unmanaged<AppHotKeyManager>.fromOpaque($0).takeUnretainedValue() }) else { return Unmanaged.passUnretained(event) }
            return manager.handle(proxy: proxy, type: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let events: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                 (1 << CGEventType.keyUp.rawValue) |
                                 (1 << CGEventType.flagsChanged.rawValue) |
                                 (1 << 14)

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

    // --- THIS IS THE CORRECTED EVENT HANDLER ---
    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        var isKeyDownEvent = false

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
            isKeyDownEvent = true

        case .keyUp:
            activeKeys.remove(keyCode)
            if activeKeys.isEmpty { lastKeyDown = nil }

        case CGEventType(rawValue: 14)!:
            guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(event)
            }
            
            let keyState = (nsEvent.data1 >> 8) & 0xFF
            
            if keyState == 0x0A {
                activeKeys.insert(keyCode)
                lastKeyDown = keyCode
                isKeyDownEvent = true
            } else if keyState == 0x0B {
                activeKeys.remove(keyCode)
                if activeKeys.isEmpty { lastKeyDown = nil }
            }
            
        default:
            return Unmanaged.passUnretained(event)
        }

        // --- Recording Logic ---
        if recordingState != nil {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                return Unmanaged.passUnretained(event)
            }
            handleRecording()
            return nil
        }
        
        // --- Cheatsheet and Hotkey Activation Logic ---
        let cheatsheetKeyCodes = Set(settings.cheatsheetShortcut.map { $0.keyCode })
        if !cheatsheetKeyCodes.isEmpty {
            let isCurrentlyMatching = cheatsheetKeyCodes == activeKeys
            if isCurrentlyMatching && !isCheatsheetHotkeyActive {
                isCheatsheetHotkeyActive = true
                NotificationCenter.default.post(name: .showCheatsheet, object: nil)
                return nil
            } else if !isCurrentlyMatching && isCheatsheetHotkeyActive {
                isCheatsheetHotkeyActive = false
                NotificationCenter.default.post(name: .hideCheatsheet, object: nil)
                return nil
            }
        }

        if isCheatsheetHotkeyActive { return nil }

        if isKeyDownEvent {
            for assignment in settings.currentProfile.wrappedValue.assignments where !assignment.shortcut.isEmpty {
                let shortcutKeyCodes = Set(assignment.shortcut.map { $0.keyCode })
                if shortcutKeyCodes == activeKeys {
                    let nonModifierKeyInShortcut = assignment.shortcut.first { !$0.isModifier }?.keyCode
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
        case 54, 55, 56, 58, 59, 60, 61, 62, 63: // Command, Shift, Option, Control, Function keys
            return true
        default:
            return false
        }
    }

    private func handleRecording() {
        if isRecordingSessionActive && !activeKeys.isEmpty {
            isRecordingSessionActive = false
            DispatchQueue.main.async { self.recordedKeys = [] }
        }

        if !isRecordingSessionActive {
            if activeKeys.count >= recordedKeys.count {
                DispatchQueue.main.async {
                    self.recordedKeys = self.activeKeys.map { aKeyCode in
                        return ShortcutKey.from(keyCode: aKeyCode, isModifier: self.isModifierKeyCode(aKeyCode))
                    }.sorted { $0.isModifier && !$1.isModifier }
                }
            }

            if activeKeys.isEmpty {
                isRecordingSessionActive = true
            }
        }
    }

    func saveRecordedShortcut() {
        guard let state = recordingState else { return }
        let finalKeys = recordedKeys.sorted { $0.isModifier && !$1.isModifier }
        if finalKeys.isEmpty { closeRecorder(); return }
        
        switch state {
        case .create(let target):
            let newAssignment = Assignment(id: UUID(), shortcut: finalKeys, configuration: .init(target: target))
            settings.addAssignment(newAssignment)
            let displayName = getDisplayName(for: target) ?? "item"
            let keyString = shortcutKeyCombinationString(for: finalKeys)
            NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "Shortcut for \(displayName) is now \(keyString).")
        case .edit(let id, let target):
            settings.updateAssignment(id: id, newShortcut: finalKeys)
            let displayName = getDisplayName(for: target) ?? "item"
            let keyString = shortcutKeyCombinationString(for: finalKeys)
            NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "Shortcut for \(displayName) is now \(keyString).")
        case .cheatsheet:
            settings.cheatsheetShortcut = finalKeys
            let keyString = shortcutKeyCombinationString(for: finalKeys)
            NotificationManager.shared.sendNotification(title: "Cheatsheet Shortcut Set!", body: "The cheatsheet hotkey is now \(keyString).")
        }
        
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
        case .edit(let id, let target):
            settings.updateAssignment(id: id, newShortcut: [])
            let displayName = getDisplayName(for: target) ?? "item"
            NotificationManager.shared.sendNotification(title: "Shortcut Cleared", body: "The hotkey for \(displayName) has been removed.")
        case .cheatsheet:
            settings.cheatsheetShortcut = []
            NotificationManager.shared.sendNotification(title: "Cheatsheet Shortcut Cleared", body: "The hotkey for the cheatsheet has been removed.")
        }
        closeRecorder()
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
        if !newlyConflictingIDs.isEmpty { }
        self.previousConflictingAssignmentIDs = self.conflictingAssignmentIDs
    }

    func handleActivation(assignment: Assignment) -> Bool {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .shortcutActivated, object: nil)
        }
        
        let config = assignment.configuration
        switch config.target {
        case .app(let bundleId):
            DispatchQueue.main.async {
                self.handleAppActivation(bundleId: bundleId, behavior: config.behavior)
            }
        case .url, .file:
             DispatchQueue.main.async {
                switch config.target {
                    case .url(let urlString): if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
                    case .file(let path): NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    default: break
                }
             }
        case .script, .shortcut:
             DispatchQueue.global(qos: .userInitiated).async {
                switch config.target {
                    case .script(let command, let runsInTerminal): self.runScript(command: command, runsInTerminal: runsInTerminal)
                    case .shortcut(let name): self.runShortcut(name: name)
                    default: break
                }
             }
        }
        
        return true
    }

    private func handleAppActivation(bundleId: String, behavior: ShortcutConfiguration.Behavior) {
        guard let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            launchAndActivate(bundleId: bundleId)
            return
        }

        if bundleId == "com.apple.finder" {
            let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
            var windows: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)

            if result == .success, let windowList = windows as? [AXUIElement] {
                let hasStandardWindow = windowList.contains { window in
                    var subrole: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
                    return (subrole as? String) == kAXStandardWindowSubrole as String
                }
                
                if !hasStandardWindow {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
                    return
                }
            }
        }

        switch behavior {
        case .activateOrHide: activateOrHide(app: targetApp)
        case .cycleWindows: cycleWindows(for: targetApp)
        }
    }

    private func forceActivate(app: NSRunningApplication) {
        guard let bundleId = app.bundleIdentifier else { return }
        
        let scriptSource = """
        tell application id "\(bundleId)"
            activate
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let err = error {
                print("AppleScript activation failed for \(bundleId): \(err)")
                app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            }
        }
    }

    private func activateOrHide(app: NSRunningApplication) {
        if app.isActive {
            app.hide()
        } else {
            forceActivate(app: app)
        }
    }

    private func cycleWindows(for app: NSRunningApplication) {
        if !app.isActive {
            forceActivate(app: app)
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var allWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &allWindows) == .success,
              let windowList = allWindows as? [AXUIElement], !windowList.isEmpty else {
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

        guard !cycleableWindows.isEmpty else {
            forceActivate(app: app)
            return
        }

        var currentMainWindowRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &currentMainWindowRef)
        let currentMainWindow = currentMainWindowRef as! AXUIElement?

        let lastIndex = self.lastCycledWindowIndex[app.processIdentifier, default: -1]
        var nextIndex = (lastIndex + 1) % cycleableWindows.count

        if let current = currentMainWindow,
           cycleableWindows[nextIndex] == current,
           cycleableWindows.count > 1 {
            nextIndex = (nextIndex + 1) % cycleableWindows.count
        }
        
        let nextWindow = cycleableWindows[nextIndex]

        AXUIElementPerformAction(nextWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, nextWindow)
        app.activate(options: .activateIgnoringOtherApps)
        self.lastCycledWindowIndex[app.processIdentifier] = nextIndex
    }

    private func launchAndActivate(bundleId: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] runningApp, error in
            guard let self = self, let app = runningApp else { return }
            DispatchQueue.main.async {
                self.forceActivate(app: app)
            }
        }
    }
    
    private func runScript(command: String, runsInTerminal: Bool) {
        if runsInTerminal {
            let appleScriptSource = """
            tell application "Terminal"
                activate
                do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
            end tell
            """
            var error: NSDictionary?
            if let script = NSAppleScript(source: appleScriptSource) {
                script.executeAndReturnError(&error)
                if let err = error { print("AppleScript Error: \(err)") }
            }
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

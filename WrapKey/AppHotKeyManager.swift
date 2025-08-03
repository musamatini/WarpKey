import SwiftUI
import AppKit
import CoreGraphics
import Combine
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Enums and Structs
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
    let isSystemEvent: Bool

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
        let lowercasedName = displayName.lowercased()
        if lowercasedName == "command" { return "⌘" }
        if lowercasedName == "option" { return "⌥" }
        if lowercasedName == "shift" { return "⇧" }
        if lowercasedName == "control" { return "⌃" }
        if lowercasedName == "function" { return "fn" }
        return displayName
    }
    
    enum CodingKeys: String, CodingKey {
        case keyCode, displayName, isModifier, isSystemEvent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(CGKeyCode.self, forKey: .keyCode)
        displayName = try container.decode(String.self, forKey: .displayName)
        isModifier = try container.decode(Bool.self, forKey: .isModifier)
        isSystemEvent = try container.decodeIfPresent(Bool.self, forKey: .isSystemEvent) ?? false
    }
    
    init(keyCode: CGKeyCode, displayName: String, isModifier: Bool, isSystemEvent: Bool) {
        self.keyCode = keyCode
        self.displayName = displayName
        self.isModifier = isModifier
        self.isSystemEvent = isSystemEvent
    }

    static func from(keyCode: CGKeyCode, isModifier: Bool, isSystemEvent: Bool) -> ShortcutKey {
        let displayName: String
        
        if keyCode == 300 {
            displayName = "Caps Lock"
        } else if isModifier {
            let names: [CGKeyCode: String] = [
                55: "Command", 54: "Command", 58: "Option", 61: "Option",
                56: "Shift", 60: "Shift", 59: "Control", 62: "Control", 63: "Function"
            ]
            displayName = names[keyCode] ?? "Mod \(keyCode)"
        } else {
            displayName = KeyboardLayout.character(for: keyCode, isSystemEvent: isSystemEvent) ?? "Key \(keyCode)"
        }
        return ShortcutKey(keyCode: keyCode, displayName: displayName, isModifier: isModifier, isSystemEvent: isSystemEvent)
    }
}

enum RecordingMode {
    case create(target: ShortcutTarget)
    case edit(assignmentID: UUID, target: ShortcutTarget)
    case cheatsheet
}

// MARK: - Main Class
class AppHotKeyManager: ObservableObject {
    @Published var hasAccessibilityPermissions: Bool
    @Published var recordingState: RecordingMode? = nil
    @Published var recordedKeys: [ShortcutKey] = []
    @Published var conflictingAssignmentIDs: Set<UUID> = []
    @Published var isCheatsheetVisible: Bool = false

    private var isCheatsheetHotkeyActive = false
    private var activeNormalKeys = Set<CGKeyCode>()
    private var activeSystemKeys = Set<CGKeyCode>()
    private var activeKeys: Set<CGKeyCode> {
        activeNormalKeys.union(activeSystemKeys)
    }
    
    private var lastKeyDown: CGKeyCode?
    private var lastCycledWindowIndex: [pid_t: Int] = [:]
    private var eventTap: CFMachPort?
    private var isMonitoringActive = false
    private var settingsCancellable: AnyCancellable?
    private var previousConflictingAssignmentIDs: Set<UUID> = []
    private var hasCapturedChord = false

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

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let specialSystemKeyCodes: Set<CGKeyCode> = [160, 176, 177, 178]
        var finalKeyCode: CGKeyCode?
        var isFunctionKey = false
        var isKeyDownEvent = false

        if type.rawValue == 14 {
            isFunctionKey = true
            guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
            finalKeyCode = CGKeyCode((nsEvent.data1 & 0xFFFF0000) >> 16)
            let keyState = (nsEvent.data1 & 0x0000FF00) >> 8
            isKeyDownEvent = (keyState == 0x0A)
        } else {
            finalKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if let code = finalKeyCode, specialSystemKeyCodes.contains(code) {
                isFunctionKey = true
            }
            isKeyDownEvent = (type == .keyDown)
        }
        
        guard let code = finalKeyCode else { return Unmanaged.passUnretained(event) }
        
        var processedKeyCode = code
        var shouldSuppressOriginalEvent = false
        
        if code == 4 || code == 57 {
            let displayName = KeyboardLayout.character(for: code, isSystemEvent: isFunctionKey) ?? "Key \(code)"
            
            if displayName == "Key 4" {
                processedKeyCode = 300
                shouldSuppressOriginalEvent = true
            }
        }
        
        if isKeyDownEvent {
            lastKeyDown = processedKeyCode
            if isFunctionKey { activeSystemKeys.insert(processedKeyCode) } else { activeNormalKeys.insert(processedKeyCode) }
        } else if type == .keyUp || (type.rawValue == 14 && !isKeyDownEvent) {
            if lastKeyDown == processedKeyCode { lastKeyDown = nil }
            activeSystemKeys.remove(processedKeyCode)
            activeNormalKeys.remove(processedKeyCode)
        } else if type == .flagsChanged {
            let flags = event.flags
            if [55, 54].contains(processedKeyCode) { if flags.contains(.maskCommand) { activeNormalKeys.insert(processedKeyCode) } else { activeNormalKeys.remove(processedKeyCode) } }
            else if [58, 61].contains(processedKeyCode) { if flags.contains(.maskAlternate) { activeNormalKeys.insert(processedKeyCode) } else { activeNormalKeys.remove(processedKeyCode) } }
            else if [56, 60].contains(processedKeyCode) { if flags.contains(.maskShift) { activeNormalKeys.insert(processedKeyCode) } else { activeNormalKeys.remove(processedKeyCode) } }
            else if [59, 62].contains(processedKeyCode) { if flags.contains(.maskControl) { activeNormalKeys.insert(processedKeyCode) } else { activeNormalKeys.remove(processedKeyCode) } }
            else if processedKeyCode == 63 { if flags.contains(.maskSecondaryFn) { activeNormalKeys.insert(processedKeyCode) } else { activeNormalKeys.remove(processedKeyCode) } }
        }

        if recordingState != nil {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier else { return Unmanaged.passUnretained(event) }
            handleRecording()
            return nil
        }
        
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
                let requiredKeyCodes = Set(assignment.shortcut.map { $0.keyCode })
                if requiredKeyCodes == self.activeKeys {
                    let triggerKey = assignment.shortcut.first { !$0.isModifier }?.keyCode
                    if processedKeyCode == triggerKey || (triggerKey == nil && lastKeyDown == processedKeyCode) {
                        if handleActivation(assignment: assignment) { return nil }
                    }
                }
            }
        }

        if shouldSuppressOriginalEvent {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Recording Logic
    private func handleRecording() {
        DispatchQueue.main.async {
            let currentActiveKeys = self.activeNormalKeys.union(self.activeSystemKeys)

            if !currentActiveKeys.isEmpty {
                if self.hasCapturedChord {
                    self.hasCapturedChord = false
                    self.recordedKeys = []
                }

                let newPotentialKeys = currentActiveKeys.map { kc -> ShortcutKey in
                    let isSystem = self.activeSystemKeys.contains(kc)
                    let isMod = self.isModifierKeyCode(kc)
                    return ShortcutKey.from(keyCode: kc, isModifier: isMod, isSystemEvent: isSystem)
                }

                if newPotentialKeys.count > self.recordedKeys.count {
                    self.recordedKeys = newPotentialKeys.sorted { $0.isModifier && !$1.isModifier }
                }
                
            } else {
                if !self.recordedKeys.isEmpty {
                    self.hasCapturedChord = true
                }
            }
        }
    }
    
    func startRecording(for mode: RecordingMode) {
        DispatchQueue.main.async {
            self.recordedKeys = []
            self.recordingState = mode
            self.hasCapturedChord = false
        }
    }

    private func closeRecorder() {
        recordingState = nil
        recordedKeys = []
        hasCapturedChord = false
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

    func saveRecordedShortcut() {
        guard let state = recordingState else { return }
        let finalKeys = recordedKeys.isEmpty && !activeKeys.isEmpty ?
            activeKeys.map { ShortcutKey.from(keyCode: $0, isModifier: isModifierKeyCode($0), isSystemEvent: activeSystemKeys.contains($0)) } :
            recordedKeys
        
        let sortedFinalKeys = finalKeys.sorted { $0.isModifier && !$1.isModifier }

        if sortedFinalKeys.isEmpty { closeRecorder(); return }
        
        switch state {
        case .create(let target):
            let newAssignment = Assignment(id: UUID(), shortcut: sortedFinalKeys, configuration: .init(target:target))
            settings.addAssignment(newAssignment)
            let displayName = getDisplayName(for: target) ?? "item"
            let keyString = shortcutKeyCombinationString(for: sortedFinalKeys)
            NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "Shortcut for \(displayName) is now \(keyString).")
        case .edit(let id, let target):
            settings.updateAssignment(id: id, newShortcut: sortedFinalKeys)
            let displayName = getDisplayName(for: target) ?? "item"
            let keyString = shortcutKeyCombinationString(for: sortedFinalKeys)
            NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "Shortcut for \(displayName) is now \(keyString).")
        case .cheatsheet:
            settings.cheatsheetShortcut = sortedFinalKeys
            let keyString = shortcutKeyCombinationString(for: sortedFinalKeys)
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
                app.activate(options: .activateIgnoringOtherApps)
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
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var allWindows: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &allWindows) == .success,
              let windowList = allWindows as? [AXUIElement], !windowList.isEmpty else {
            forceActivate(app: app)
            return
        }

        let filteredWindows = windowList.filter { window in
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            if let subrole = subrole as? String, subrole == kAXStandardWindowSubrole as String {
                var isMinimized: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized)
                return (isMinimized as? NSNumber)?.boolValue == false
            }
            return false
        }
        
        let cycleableWindows = filteredWindows.sorted { window1, window2 in
            var id1: CFTypeRef?
            var id2: CFTypeRef?
            AXUIElementCopyAttributeValue(window1, kAXIdentifierAttribute as CFString, &id1)
            AXUIElementCopyAttributeValue(window2, kAXIdentifierAttribute as CFString, &id2)
            
            if let idStr1 = id1 as? String, let idStr2 = id2 as? String {
                return idStr1 < idStr2
            }
            
            var title1: CFTypeRef?
            var title2: CFTypeRef?
            var pos1: CFTypeRef?
            var pos2: CFTypeRef?
            
            AXUIElementCopyAttributeValue(window1, kAXTitleAttribute as CFString, &title1)
            AXUIElementCopyAttributeValue(window2, kAXTitleAttribute as CFString, &title2)
            AXUIElementCopyAttributeValue(window1, kAXPositionAttribute as CFString, &pos1)
            AXUIElementCopyAttributeValue(window2, kAXPositionAttribute as CFString, &pos2)
            
            let titleStr1 = (title1 as? String) ?? ""
            let titleStr2 = (title2 as? String) ?? ""
            
            if titleStr1 != titleStr2 {
                return titleStr1 < titleStr2
            }
            
            if let point1 = pos1, let point2 = pos2 {
                var cgPoint1 = CGPoint.zero
                var cgPoint2 = CGPoint.zero
                if AXValueGetValue(point1 as! AXValue, .cgPoint, &cgPoint1),
                   AXValueGetValue(point2 as! AXValue, .cgPoint, &cgPoint2) {
                    if cgPoint1.x != cgPoint2.x {
                        return cgPoint1.x < cgPoint2.x
                    }
                    return cgPoint1.y < cgPoint2.y
                }
            }
            
            return false
        }

        if cycleableWindows.count <= 1 {
            activateOrHide(app: app)
            return
        }
        
        var currentMainWindowRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &currentMainWindowRef)
        let currentMainWindow = currentMainWindowRef as! AXUIElement?
        
        var currentIndex = -1
        if let current = currentMainWindow {
            for (index, window) in cycleableWindows.enumerated() {
                var currentTitle: CFTypeRef?
                var windowTitle: CFTypeRef?
                var currentPos: CFTypeRef?
                var windowPos: CFTypeRef?
                
                AXUIElementCopyAttributeValue(current, kAXTitleAttribute as CFString, &currentTitle)
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &windowTitle)
                AXUIElementCopyAttributeValue(current, kAXPositionAttribute as CFString, &currentPos)
                AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &windowPos)
                
                let currentTitleStr = (currentTitle as? String) ?? ""
                let windowTitleStr = (windowTitle as? String) ?? ""
                
                if currentTitleStr == windowTitleStr {
                    if let cp = currentPos, let wp = windowPos {
                        var cgPoint1 = CGPoint.zero
                        var cgPoint2 = CGPoint.zero
                        if AXValueGetValue(cp as! AXValue, .cgPoint, &cgPoint1),
                           AXValueGetValue(wp as! AXValue, .cgPoint, &cgPoint2) {
                            if cgPoint1.x == cgPoint2.x && cgPoint1.y == cgPoint2.y {
                                currentIndex = index
                                break
                            }
                        }
                    } else if currentTitleStr != "" {
                        currentIndex = index
                        break
                    }
                }
            }
        }
        
        if !app.isActive {
            currentIndex = -1
        }
        
        let nextIndex = (currentIndex + 1) % cycleableWindows.count
        let nextWindow = cycleableWindows[nextIndex]

        AXUIElementPerformAction(nextWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, nextWindow)
        app.activate(options: .activateIgnoringOtherApps)
        
        print("Cycled from index \(currentIndex) to \(nextIndex) of \(cycleableWindows.count) windows")
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

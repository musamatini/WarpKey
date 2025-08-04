import SwiftUI
import AppKit
import CoreGraphics
import Combine
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Enums and Structs
fileprivate enum InternalShortcutID: String {
    case cheatsheet = "dev.wrapkey.internal.cheatsheet"
    case quickAssign = "dev.wrapkey.internal.quickassign"
}

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

enum RecordingMode: Equatable {
    case create(target: ShortcutTarget)
    case edit(assignmentID: UUID, target: ShortcutTarget)
    case cheatsheet
    case appAssigning(target: ShortcutTarget)
}

// MARK: - Main Class
class AppHotKeyManager: ObservableObject {
    @Published var hasAccessibilityPermissions: Bool
    @Published var recordingState: RecordingMode? = nil
    @Published var recordedKeys: [ShortcutKey] = []
    @Published var recordedTriggerType: ShortcutTriggerType = .press
    @Published var conflictingAssignmentIDs: Set<UUID> = []
    
    private var appNameCache: [String: String] = [:]
    private var appIconCache: [String: NSImage] = [:]
    private var activeNormalKeys = Set<CGKeyCode>()
    private var activeSystemKeys = Set<CGKeyCode>()
    var activeKeys: Set<CGKeyCode> {
        activeNormalKeys.union(activeSystemKeys)
    }
    
    private var eventTap: CFMachPort?
    private var isMonitoringActive = false
    private var activationsInProgress = Set<String>()
    private var hotkeyCache: [String: [Assignment]] = [:]
    private var settingsCancellable: AnyCancellable?
    private var permissionCheckTimer: Timer?
    private var originalKeysForEdit: [ShortcutKey] = []
    private var originalTriggerForEdit: ShortcutTriggerType = .press
    private var hasCapturedChord = false

    private struct PressInfo {
        var count: Int = 0
        var lastPressTime: TimeInterval = 0
        var dispatchWorkItem: DispatchWorkItem?
        var holdTimer: Timer?
        var holdActionFired: Bool = false
    }
    private var pressTracker: [String: PressInfo] = [:]
    private let multiPressThreshold: TimeInterval = 0.4
    private let holdThreshold: TimeInterval = 0.5
    
    var settings: SettingsManager
    
    init(settings: SettingsManager) {
        self.settings = settings
        self.hasAccessibilityPermissions = AccessibilityManager.checkPermissions()

        settingsCancellable = settings.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkForConflicts()
                self?.updateHotkeyCache()
            }
        
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopMonitoring()
        }
        
        updateHotkeyCache()
        startMonitoring()
        checkForConflicts()
        startPermissionMonitoring()
    }

    deinit {
        stopMonitoring()
        stopPermissionMonitoring()
        settingsCancellable?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Monitoring & Permissions
    
    func startPermissionMonitoring() {
        stopPermissionMonitoring()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPermissionStatus()
        }
    }

    func restartMonitoringIfNeeded() {
        if hasAccessibilityPermissions && !isMonitoringActive {
            restartMonitoring()
        }
    }
    
    @objc private func checkPermissionStatus() {
        let currentStatus = AccessibilityManager.checkPermissions()
        if self.hasAccessibilityPermissions != currentStatus {
            self.hasAccessibilityPermissions = currentStatus
            if !currentStatus {
                stopMonitoring()
            }
        }
    }
    
    func stopPermissionMonitoring() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
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
        let events: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)

        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: events, callback: eventTapCallback, userInfo: selfPtr)

        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isMonitoringActive = true
        } else {
            isMonitoringActive = false
            NotificationCenter.default.post(name: .accessibilityPermissionsLost, object: nil)
        }
    }

    public func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
            isMonitoringActive = false
        }
        pressTracker.values.forEach { $0.holdTimer?.invalidate(); $0.dispatchWorkItem?.cancel() }
        pressTracker.removeAll()
    }
    
    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                self.stopMonitoring()
                self.hasAccessibilityPermissions = false
                NotificationCenter.default.post(name: .accessibilityPermissionsLost, object: nil)
            }
            return Unmanaged.passRetained(event)
        }

        var finalKeyCode: CGKeyCode?
        var isKeyDownEvent = false

        if type.rawValue == 14 {
            guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(event)
            }
            finalKeyCode = CGKeyCode((nsEvent.data1 & 0xFFFF0000) >> 16)
            isKeyDownEvent = ((nsEvent.data1 & 0x0000FF00) >> 8) == 0x0A
        } else {
            finalKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            isKeyDownEvent = (type == .keyDown)
        }
        
        guard let code = finalKeyCode else { return Unmanaged.passUnretained(event) }
        
        var processedKeyCode = code
        if code == 4 || code == 57 {
            if (KeyboardLayout.character(for: code, isSystemEvent: type.rawValue == 14) ?? "") == "Key 4" {
                processedKeyCode = 300
            }
        }
        
        let previousActiveKeys = activeKeys

        if isKeyDownEvent {
            if type.rawValue == 14 { activeSystemKeys.insert(processedKeyCode) } else { activeNormalKeys.insert(processedKeyCode) }
        } else if type == .keyUp || (type.rawValue == 14 && !isKeyDownEvent) {
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
        
        if let state = recordingState {
            let isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            
            let requiresFrontmost: Bool
            switch state {
            case .create, .edit, .cheatsheet: requiresFrontmost = true
            case .appAssigning: requiresFrontmost = false
            }
            
            if !requiresFrontmost || isFrontmost {
                handleRecording()
                return nil
            }
        }

        var shouldSuppressEvent = false
        let nonModifierKey = isModifierKeyCode(processedKeyCode) ? nil : processedKeyCode
        
        if isKeyDownEvent, let triggerKey = nonModifierKey {
            shouldSuppressEvent = handleKeyDown(for: triggerKey, with: activeKeys)
        } else if type == .keyUp, let triggerKey = nonModifierKey {
            shouldSuppressEvent = handleKeyUp(for: triggerKey, with: previousActiveKeys)
        } else if type == .keyUp && activeKeys.isEmpty {
            let comboId = previousActiveKeys.map { String($0) }.sorted().joined(separator: "-")
            if pressTracker[comboId]?.holdTimer != nil {
                pressTracker[comboId]?.holdTimer?.invalidate()
                pressTracker[comboId] = nil
            }
        }

        if shouldSuppressEvent {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Hotkey Logic

    private func updateHotkeyCache() {
        hotkeyCache.removeAll()
        var allAssignments = settings.currentProfile.wrappedValue.assignments
        
        let quickAssignAssignment = Assignment(
            id: UUID(),
            shortcut: settings.appAssigningShortcut.keys,
            trigger: settings.appAssigningShortcut.trigger,
            configuration: .init(target: .app(bundleId: InternalShortcutID.quickAssign.rawValue))
        )
        allAssignments.append(quickAssignAssignment)

        for assignment in allAssignments {
            if assignment.shortcut.isEmpty { continue }
            let keyString = assignment.shortcut
                .map { String($0.keyCode) }
                .sorted()
                .joined(separator: "-")
            hotkeyCache[keyString, default: []].append(assignment)
        }
    }

    private func handleKeyDown(for triggerKey: CGKeyCode, with keyCombination: Set<CGKeyCode>) -> Bool {
        let comboId = keyCombination.map { String($0) }.sorted().joined(separator: "-")
        let cheatsheetComboId = settings.cheatsheetShortcut.keys.map { String($0.keyCode) }.sorted().joined(separator: "-")

        if !cheatsheetComboId.isEmpty && comboId == cheatsheetComboId {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showCheatsheet, object: nil)
            }
            return true
        }

        guard let assignments = hotkeyCache[comboId], !assignments.isEmpty else { return false }
        
        if pressTracker[comboId]?.holdTimer != nil || pressTracker[comboId]?.holdActionFired == true {
            return true
        }
        
        pressTracker[comboId]?.dispatchWorkItem?.cancel()

        let holdAssignments = assignments.filter({ $0.trigger == .hold })
        if !holdAssignments.isEmpty {
            let timer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
                guard let self = self, self.activeKeys == keyCombination else {
                    self?.pressTracker[comboId]?.holdActionFired = false
                    return
                }
                
                for assignment in holdAssignments {
                    _ = self.handleActivation(assignment: assignment)
                }
                self.pressTracker[comboId, default: PressInfo()].holdActionFired = true
            }
            pressTracker[comboId, default: PressInfo()].holdTimer = timer
        }
        return true
    }
    
    private func handleKeyUp(for triggerKey: CGKeyCode, with keyCombination: Set<CGKeyCode>) -> Bool {
        let comboId = keyCombination.map { String($0) }.sorted().joined(separator: "-")
        let cheatsheetComboId = settings.cheatsheetShortcut.keys.map { String($0.keyCode) }.sorted().joined(separator: "-")

        if !cheatsheetComboId.isEmpty && comboId == cheatsheetComboId {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .hideCheatsheet, object: nil)
            }
            return true
        }

        guard let assignments = hotkeyCache[comboId], !assignments.isEmpty else { return false }

        pressTracker[comboId]?.holdTimer?.invalidate()
        pressTracker[comboId]?.holdTimer = nil
        
        if pressTracker[comboId]?.holdActionFired == true {
            pressTracker[comboId] = nil
            return true
        }
        
        var info = pressTracker[comboId, default: PressInfo()]
        let now = CACurrentMediaTime()
        
        if (now - info.lastPressTime) > multiPressThreshold { info.count = 0 }
        
        info.count += 1
        let currentCount = info.count
        info.lastPressTime = now
                
        switch currentCount {
        case 1:
            let hasMultiPressSibling = assignments.contains { $0.trigger == .doublePress || $0.trigger == .triplePress }
            if !hasMultiPressSibling {
                if let assignment = assignments.first(where: { $0.trigger == .press }) {
                    _ = self.handleActivation(assignment: assignment)
                }
                pressTracker[comboId] = nil
                return true
            }
            
        case 2:
            let hasTriplePressSibling = assignments.contains { $0.trigger == .triplePress }
            if !hasTriplePressSibling {
                if let assignment = assignments.first(where: { $0.trigger == .doublePress }) {
                    _ = self.handleActivation(assignment: assignment)
                }
                pressTracker[comboId] = nil
                return true
            }
            
        case 3:
            if let assignment = assignments.first(where: { $0.trigger == .triplePress }) {
                _ = self.handleActivation(assignment: assignment)
            }
            pressTracker[comboId] = nil
            return true
            
        default:
            pressTracker[comboId] = nil
            return true
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            let triggerType: ShortcutTriggerType?
            switch currentCount {
            case 1: triggerType = .press
            case 2: triggerType = .doublePress
            default: triggerType = nil
            }
            
            if let type = triggerType {
                let matchingAssignments = assignments.filter({ $0.trigger == type })
                for assignment in matchingAssignments {
                    _ = self.handleActivation(assignment: assignment)
                }
            }
            self.pressTracker[comboId] = nil
        }
        
        info.dispatchWorkItem = workItem
        pressTracker[comboId] = info
        DispatchQueue.main.asyncAfter(deadline: .now() + multiPressThreshold, execute: workItem)
        
        return true
    }

    // MARK: - Recording Logic
    
    private func handleRecording() {
        DispatchQueue.main.async {
            let currentActiveKeys = self.activeKeys

            if !currentActiveKeys.isEmpty {
                if self.hasCapturedChord {
                    self.recordedKeys = []
                    self.hasCapturedChord = false
                }

                let newKeys = currentActiveKeys.map { kc -> ShortcutKey in
                    ShortcutKey.from(keyCode: kc, isModifier: self.isModifierKeyCode(kc), isSystemEvent: self.activeSystemKeys.contains(kc))
                }.sorted { $0.isModifier && !$1.isModifier }
                
                if newKeys.count >= self.recordedKeys.count {
                    self.recordedKeys = newKeys
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
            self.recordingState = mode
            self.hasCapturedChord = false
            
            switch mode {
            case .create:
                self.recordedKeys = []
                self.recordedTriggerType = .press
                self.originalKeysForEdit = []
                self.originalTriggerForEdit = .press
            case .edit(let id, _):
                if let assignment = self.settings.currentProfile.wrappedValue.assignments.first(where: { $0.id == id }) {
                    self.recordedKeys = assignment.shortcut
                    self.recordedTriggerType = assignment.trigger
                    self.originalKeysForEdit = assignment.shortcut
                    self.originalTriggerForEdit = assignment.trigger
                }
            case .cheatsheet:
                let shortcut = self.settings.cheatsheetShortcut
                self.recordedKeys = shortcut.keys
                self.recordedTriggerType = shortcut.trigger
                self.originalKeysForEdit = shortcut.keys
                self.originalTriggerForEdit = shortcut.trigger
            case .appAssigning:
                self.recordedKeys = []
                self.recordedTriggerType = .press
                self.originalKeysForEdit = []
                self.originalTriggerForEdit = .press
            }
        }
    }

    private func closeRecorder() {
        self.recordingState = nil
        self.recordedKeys = []
        NotificationCenter.default.post(name: .hideAssigningOverlay, object: nil)
    }

    func cancelRecording() { closeRecorder() }

    private func isModifierKeyCode(_ keyCode: CGKeyCode) -> Bool {
        return [54, 55, 56, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
    
    func saveRecordedShortcut() {
        guard let state = recordingState else { return }

        let finalKeys = self.recordedKeys
        
        let hasKeys = !finalKeys.isEmpty
        let keysChanged = finalKeys != originalKeysForEdit
        let triggerChanged = recordedTriggerType != originalTriggerForEdit

        if case .create = state {
            guard hasKeys else { closeRecorder(); return }
        } else if case .appAssigning = state {
            guard hasKeys else { closeRecorder(); return }
        } else {
            if case .cheatsheet = state {
                guard keysChanged else { closeRecorder(); return }
            } else {
                guard keysChanged || triggerChanged else { closeRecorder(); return }
            }
        }
        
        switch state {
        case .create(let target):
            let newAssignment = Assignment(shortcut: finalKeys, trigger: self.recordedTriggerType, configuration: .init(target:target))
            settings.addAssignment(newAssignment)
            NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "Shortcut for \(getDisplayName(for: target) ?? "item") is now \(shortcutKeyCombinationString(for: finalKeys)).")
        case .edit(let id, let target):
            settings.updateAssignment(id: id, newShortcut: finalKeys, newTrigger: self.recordedTriggerType)
            NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "Shortcut for \(getDisplayName(for: target) ?? "item") is now \(shortcutKeyCombinationString(for: finalKeys)).")
        case .cheatsheet:
            settings.cheatsheetShortcut = SpecialShortcut(keys: finalKeys, trigger: .press)
            NotificationManager.shared.sendNotification(title: "Cheatsheet Shortcut Set!", body: "The cheatsheet hotkey is now \(shortcutKeyCombinationString(for: finalKeys)).")
        case .appAssigning(let target):
            let newAssignment = Assignment(shortcut: finalKeys, trigger: self.recordedTriggerType, configuration: .init(target:target))
            settings.addAssignment(newAssignment)
            NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "Shortcut for \(getDisplayName(for: target) ?? "item") is now \(shortcutKeyCombinationString(for: finalKeys)).")
        }
        
        closeRecorder()
    }

    func clearRecordedShortcut() {
        guard let state = recordingState else { return }
        switch state {
        case .create(let target):
            let newAssignment = Assignment(shortcut: [], configuration: .init(target: target))
            settings.addAssignment(newAssignment)
            NotificationManager.shared.sendNotification(title: "Shortcut Added", body: "\(getDisplayName(for: target) ?? "item") was added without a hotkey.")
        case .edit(let id, let target):
            settings.updateAssignment(id: id, newShortcut: [])
            NotificationManager.shared.sendNotification(title: "Shortcut Cleared", body: "The hotkey for \(getDisplayName(for: target) ?? "item") has been removed.")
        case .cheatsheet:
            settings.cheatsheetShortcut = SpecialShortcut(keys: [], trigger: .press)
            NotificationManager.shared.sendNotification(title: "Cheatsheet Shortcut Cleared", body: "The hotkey for the cheatsheet has been removed.")
        case .appAssigning:
            closeRecorder()
        }
        closeRecorder()
    }

    // MARK: - Activation Logic

    func handleActivation(assignment: Assignment) -> Bool {
        guard let bundleId = assignment.configuration.target.bundleId else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .shortcutActivated, object: nil) }
            
            let config = assignment.configuration
            switch config.target {
            case .app(let bundleId): DispatchQueue.main.async { self.handleAppActivation(bundleId: bundleId, behavior: config.behavior) }
            case .url(let urlString): DispatchQueue.main.async { if let url = URL(string: urlString) { NSWorkspace.shared.open(url) } }
            case .file(let path): DispatchQueue.main.async { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            case .script(let command, let runsInTerminal): DispatchQueue.global(qos: .userInitiated).async { self.runScript(command: command, runsInTerminal: runsInTerminal) }
            case .shortcut(let name): DispatchQueue.global(qos: .userInitiated).async { self.runShortcut(name: name) }
            }
            return true
        }

        switch InternalShortcutID(rawValue: bundleId) {
        case .cheatsheet:
            if activeKeys.isEmpty {
                DispatchQueue.main.async { NotificationCenter.default.post(name: .hideCheatsheet, object: nil) }
            } else {
                DispatchQueue.main.async { NotificationCenter.default.post(name: .showCheatsheet, object: nil) }
            }
            return true
        case .quickAssign:
            if activeKeys.isEmpty {
                 DispatchQueue.main.async { self.cancelRecording() }
            } else {
                DispatchQueue.main.async {
                    guard let frontmostApp = NSWorkspace.shared.frontmostApplication, let id = frontmostApp.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
                    self.startRecording(for: .appAssigning(target: .app(bundleId: id)))
                    NotificationCenter.default.post(name: .showAssigningOverlay, object: nil)
                }
            }
            return true
        case .none:
            DispatchQueue.main.async { NotificationCenter.default.post(name: .shortcutActivated, object: nil) }
            handleAppActivation(bundleId: bundleId, behavior: assignment.configuration.behavior)
            return true
        }
    }



        private func forceReopenAndActivate(app: NSRunningApplication) {
            // This is the most robust way to bring an app to the front and ensure it has a window.
            // 'reopen' is the command that mimics clicking an app in the Dock.
            guard let bundleId = app.bundleIdentifier else { return }
            
            let scriptSource = """
            tell application id "\(bundleId)"
                reopen
                activate
            end tell
            """
            
            if let script = NSAppleScript(source: scriptSource) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                if let err = error {
                    print("AppleScript reopen/activate failed for \(bundleId): \(err)")
                    DispatchQueue.main.async {
                        app.activate(options: [.activateIgnoringOtherApps])
                    }
                }
            }
        }

        private func activateOrHide(app: NSRunningApplication) {
            if app.isActive {
                app.hide()
            } else {
                self.forceReopenAndActivate(app: app)
            }
        }

    
    private func handleAppActivation(bundleId: String, behavior: ShortcutConfiguration.Behavior) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                if self.activationsInProgress.contains(bundleId) { return }
                self.activationsInProgress.insert(bundleId)
                defer { DispatchQueue.main.async { self.activationsInProgress.remove(bundleId) } }
                
                if bundleId == "com.apple.finder" {
                    let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
                    var windows: CFTypeRef?
                    if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows) == .success, let windowList = windows as? [AXUIElement],
                       !windowList.contains(where: { w -> Bool in
                           var sr: CFTypeRef?; AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &sr)
                           return (sr as? String) == kAXStandardWindowSubrole as String
                       }) {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
                        return
                    }
                }
                
                switch behavior {
                case .activateOrHide: self.activateOrHide(app: targetApp)
                case .cycleWindows: self.cycleWindows(for: targetApp)
                }
            } else {
                self.launchAndActivate(bundleId: bundleId)
            }
        }
    }

    private func launchAndActivate(bundleId: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] runningApp, error in
            guard let self = self, let app = runningApp, error == nil else {
                if let err = error { print("Failed to launch \(bundleId): \(err.localizedDescription)") }
                return
            }
            self.forceReopenAndActivate(app: app)
        }
    }


    private func cycleWindows(for app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var allWindows: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &allWindows) == .success,
              let windowList = allWindows as? [AXUIElement], !windowList.isEmpty else {
            forceReopenAndActivate(app: app)
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
            var title1: CFTypeRef?; var title2: CFTypeRef?
            AXUIElementCopyAttributeValue(window1, kAXTitleAttribute as CFString, &title1)
            AXUIElementCopyAttributeValue(window2, kAXTitleAttribute as CFString, &title2)
            let titleStr1 = (title1 as? String) ?? ""; let titleStr2 = (title2 as? String) ?? ""
            if titleStr1 != titleStr2 { return titleStr1 < titleStr2 }
            
            var pos1: CFTypeRef?; var pos2: CFTypeRef?
            AXUIElementCopyAttributeValue(window1, kAXPositionAttribute as CFString, &pos1)
            AXUIElementCopyAttributeValue(window2, kAXPositionAttribute as CFString, &pos2)
            if let point1Val = pos1 as! AXValue?, let point2Val = pos2 as! AXValue? {
                var cgPoint1 = CGPoint.zero; var cgPoint2 = CGPoint.zero
                if AXValueGetValue(point1Val, .cgPoint, &cgPoint1), AXValueGetValue(point2Val, .cgPoint, &cgPoint2) {
                    if cgPoint1.y != cgPoint2.y { return cgPoint1.y < cgPoint2.y }
                    return cgPoint1.x < cgPoint2.x
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
        
        var currentIndex = -1
        if app.isActive, let currentMainWindow = currentMainWindowRef as! AXUIElement? {
            currentIndex = cycleableWindows.firstIndex(where: { $0 == currentMainWindow }) ?? -1
        }
        
        let nextIndex = (currentIndex + 1) % cycleableWindows.count
        let nextWindow = cycleableWindows[nextIndex]

        AXUIElementPerformAction(nextWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, nextWindow as CFTypeRef)
        self.forceReopenAndActivate(app: app)
    }

    private func launchWithoutActivating(bundleId: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        let config = NSWorkspace.OpenConfiguration(); config.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }

    // MARK: - Utility Functions

    private func checkForConflicts() {
        var hotkeys: [String: [UUID]] = [:]
        for assignment in settings.currentProfile.wrappedValue.assignments {
            if assignment.shortcut.isEmpty { continue }
            let sortedKeyCodes = assignment.shortcut.map { String($0.keyCode) }.sorted()
            let hotkeyID = sortedKeyCodes.joined(separator: "-") + "-\(assignment.trigger.rawValue)"
            hotkeys[hotkeyID, default: []].append(assignment.id)
        }
        let currentConflicts = hotkeys.values.filter { $0.count > 1 }.flatMap { $0 }
        self.conflictingAssignmentIDs = Set(currentConflicts)
    }
    
    private func runScript(command: String, runsInTerminal: Bool) { if runsInTerminal { let appleScriptSource = "tell application \"Terminal\"\nactivate\ndo script \"\(command.replacingOccurrences(of: "\"", with: "\\\""))\"\nend tell"; var error: NSDictionary?; if let script = NSAppleScript(source: appleScriptSource) { script.executeAndReturnError(&error); if let err = error { print("AppleScript Error: \(err)") } } } else { let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/zsh"); task.arguments = ["-c", command]; do { try task.run() } catch { print("Failed to run script in background: \(error)") } } }
    
    private func runShortcut(name: String) { let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); task.arguments = ["run", name]; do { try task.run() } catch { print("Failed to run shortcut '\(name)': \(error)"); NotificationManager.shared.sendNotification(title: "Shortcut Failed", body: "Could not run '\(name)'.") } }
    
    func getDisplayName(for target: ShortcutTarget) -> String? { switch target { case .app(let bundleId): return getAppName(for: bundleId); case .url(let urlString): return URL(string: urlString)?.host ?? "URL"; case .file(let path): return URL(fileURLWithPath: path).lastPathComponent; case .script: return "Script"; case .shortcut(let name): return name } }
    
    func getAppName(for bundleId: String) -> String? {
        if let cachedName = appNameCache[bundleId] {
            return cachedName
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            appNameCache[bundleId] = bundleId
            return bundleId
        }

        if let bundle = Bundle(url: url) {
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
                appNameCache[bundleId] = name
                return name
            }
        }
        
        let fallbackName = FileManager.default.displayName(atPath: url.path)
        appNameCache[bundleId] = fallbackName
        return fallbackName
    }
    func getAppIcon(for bundleId: String) -> NSImage? {
        if let cachedIcon = appIconCache[bundleId] {
            return cachedIcon
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        appIconCache[bundleId] = icon
        return icon
    }
    func getIcon(for target: ShortcutTarget, size: NSSize = NSSize(width: 18, height: 18)) -> NSImage? { let image: NSImage?; switch target { case .app(let bundleId): image = getAppIcon(for: bundleId); case .url: image = NSImage(systemSymbolName: "globe", accessibilityDescription: "URL"); case .file: image = NSImage(systemSymbolName: "doc", accessibilityDescription: "File"); case .script: image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Script"); case .shortcut: image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Shortcut") }; image?.size = size; if target.category != .app { image?.isTemplate = true }; return image }
    
    func shortcutKeyCombinationString(for keys: [ShortcutKey]) -> String { if keys.isEmpty { return "Not Set" }; return keys.map { $0.symbol }.joined(separator: " + ") }
}

fileprivate extension ShortcutTarget {
    var bundleId: String? {
        if case .app(let id) = self {
            return id
        }
        return nil
    }
}

// AppHotKeyManager.swift

import SwiftUI
import AppKit
import CoreGraphics
import Combine
import Carbon.HIToolbox
import ApplicationServices
import CoreServices
import UniformTypeIdentifiers

fileprivate let systemKeyOffset: CGKeyCode = 1000

fileprivate enum InternalShortcutID: String {
    case cheatsheet = "dev.WarpKey.internal.cheatsheet"
    case quickAssign = "dev.WarpKey.internal.quickassign"
}

fileprivate enum ConflictableIdentifier {
    case assignment(id: UUID)
    case cheatsheet
    case quickAssign

    var stringValue: String {
        switch self {
        case .assignment(let id): return id.uuidString
        case .cheatsheet: return "internal_cheatsheet"
        case .quickAssign: return "internal_quickassign"
        }
    }
}

enum ShortcutTarget: Hashable {
    case app(name: String, bundleId: String)
    case url(name: String, address: String)
    case file(name: String, path: String)
    case script(name: String, command: String, runsInTerminal: Bool)
    case shortcut(name: String, executionName: String)
    case snippet(name: String, content: String)

    var category: ShortcutCategory {
        switch self {
        case .app: .app
        case .url: .url
        case .file: .file
        case .script: .script
        case .shortcut: .shortcut
        case .snippet: .snippet
        }
    }

    var displayName: String {
        switch self {
        case .app(let name, _), .url(let name, _), .file(let name, _), .script(let name, _, _), .shortcut(let name, _), .snippet(let name, _):
            return name
        }
    }
    
    private func generateShortcutIcon(forName name: String, size: NSSize) -> NSImage {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo,
            .purple, .pink, .brown
        ]
        
        let colorIndex = abs(name.hashValue) % colors.count
        let backgroundColor = colors[colorIndex]
        
        let firstLetter = String(name.first ?? "?").uppercased()

        let iconView = ZStack {
            RoundedRectangle(cornerRadius: size.width * 0.22, style: .continuous)
                .fill(backgroundColor)
            
            Text(firstLetter)
                .font(.system(size: size.width * 0.6, weight: .medium, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size.width, height: size.height)
        
        let hostingView = NSHostingView(rootView: iconView)
        hostingView.frame = CGRect(origin: .zero, size: size)
        
        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)!
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    func getIcon(using manager: AppHotKeyManager, size: NSSize = NSSize(width: 18, height: 18)) -> NSImage? {
        let image: NSImage?
        switch self {
        case .app(_, let bundleId):
            image = manager.getAppIcon(for: bundleId)
            
        case .url:
            image = NSImage(systemSymbolName: "link", accessibilityDescription: "URL")
            
        case .file(_, let path):
            image = NSWorkspace.shared.icon(forFile: path)
            
        case .script:
            image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Script")
            
        case .shortcut(let name, _):
            image = generateShortcutIcon(forName: name, size: size)
            
        case .snippet:
            image = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: "Snippet")
        }
        
        image?.size = size
        
        if self.category == .url || self.category == .script || self.category == .snippet {
            image?.isTemplate = true
        }
        
        return image
    }
}

extension ShortcutTarget: Codable {
    enum CodingKeys: CodingKey {
        case type, payload
    }
    
    enum PayloadKeys: String, CodingKey {
        case name, bundleId, address, path, command, runsInTerminal, executionName, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ShortcutCategory.self, forKey: .type)
        let payload = try container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)

        switch type {
        case .app:
            self = .app(name: try payload.decode(String.self, forKey: .name), bundleId: try payload.decode(String.self, forKey: .bundleId))
        case .url:
            self = .url(name: try payload.decode(String.self, forKey: .name), address: try payload.decode(String.self, forKey: .address))
        case .file:
            self = .file(name: try payload.decode(String.self, forKey: .name), path: try payload.decode(String.self, forKey: .path))
        case .script:
            self = .script(name: try payload.decode(String.self, forKey: .name), command: try payload.decode(String.self, forKey: .command), runsInTerminal: try payload.decode(Bool.self, forKey: .runsInTerminal))
        case .shortcut:
            self = .shortcut(name: try payload.decode(String.self, forKey: .name), executionName: try payload.decode(String.self, forKey: .executionName))
        case .snippet:
            self = .snippet(name: try payload.decode(String.self, forKey: .name), content: try payload.decode(String.self, forKey: .content))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.category, forKey: .type)
        var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)

        switch self {
        case .app(let name, let bundleId):
            try payload.encode(name, forKey: .name)
            try payload.encode(bundleId, forKey: .bundleId)
        case .url(let name, let address):
            try payload.encode(name, forKey: .name)
            try payload.encode(address, forKey: .address)
        case .file(let name, let path):
            try payload.encode(name, forKey: .name)
            try payload.encode(path, forKey: .path)
        case .shortcut(let name, let executionName):
            try payload.encode(name, forKey: .name)
            try payload.encode(executionName, forKey: .executionName)
        case .script(let name, let command, let runsInTerminal):
            try payload.encode(name, forKey: .name)
            try payload.encode(command, forKey: .command)
            try payload.encode(runsInTerminal, forKey: .runsInTerminal)
        case .snippet(let name, let content):
            try payload.encode(name, forKey: .name)
            try payload.encode(content, forKey: .content)
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
        let lookupKeyCode = isSystemEvent ? (keyCode - systemKeyOffset) : keyCode

        if lookupKeyCode == 300 {
            displayName = "Caps Lock"
        } else if isModifier {
            let names: [CGKeyCode: String] = [
                55: "Command", 54: "Command", 58: "Option", 61: "Option",
                56: "Shift", 60: "Shift", 59: "Control", 62: "Control", 63: "Function"
            ]
            displayName = names[lookupKeyCode] ?? "Mod \(lookupKeyCode)"
        } else {
            displayName = KeyboardLayout.character(for: lookupKeyCode, isSystemEvent: isSystemEvent) ?? "Key \(lookupKeyCode)"
        }
        return ShortcutKey(keyCode: keyCode, displayName: displayName, isModifier: isModifier, isSystemEvent: isSystemEvent)
    }
}

enum RecordingMode: Equatable {
    case create(target: ShortcutTarget)
    case edit(assignmentID: UUID, target: ShortcutTarget)
    case cheatsheet
    case quickAssign
    case appAssigning(target: ShortcutTarget)
}

class AppHotKeyManager: ObservableObject {
    @Published var hasAccessibilityPermissions: Bool
    @Published var hasScreenRecordingPermissions: Bool
    @Published var recordingState: RecordingMode? = nil
    @Published var recordedKeys: [ShortcutKey] = []
    @Published var recordedTriggerType: ShortcutTriggerType = .press
    @Published var conflictingAssignmentIDs: Set<UUID> = []
    @Published var isCheatsheetConflicting = false
    @Published var isQuickAssignConflicting = false
    
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
    private let holdThreshold: TimeInterval = 0.4
    
    var settings: SettingsManager
    
    init(settings: SettingsManager) {
        self.settings = settings
        self.hasAccessibilityPermissions = AccessibilityManager.checkPermissions()
        self.hasScreenRecordingPermissions = AccessibilityManager.checkScreenRecordingPermissions()

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
        WindowFocusManager.startMonitoring()
    }

    deinit {
        stopMonitoring()
        stopPermissionMonitoring()
        WindowFocusManager.stopMonitoring()
        settingsCancellable?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    
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
        let accStatus = AccessibilityManager.checkPermissions()
        let recStatus = AccessibilityManager.checkScreenRecordingPermissions()

        let accessibilityLost = self.hasAccessibilityPermissions && !accStatus
        let recordingLost = self.hasScreenRecordingPermissions && !recStatus

        if accessibilityLost || recordingLost {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .permissionsRevoked, object: nil)
            }
        }
        
        self.hasAccessibilityPermissions = accStatus
        self.hasScreenRecordingPermissions = recStatus
        
        if accessibilityLost {
            stopMonitoring()
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

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .flagsChanged && keyCode == 57 { // CAPS LOCK
            let logicalCapsLockKey: CGKeyCode = 300
            let capsOn = event.flags.contains(.maskAlphaShift)
            
            if recordingState != nil {
                DispatchQueue.main.async {
                    let capsKey = ShortcutKey.from(keyCode: logicalCapsLockKey, isModifier: false, isSystemEvent: false)
                    if self.hasCapturedChord { self.recordedKeys = []; self.hasCapturedChord = false }
                    if !self.recordedKeys.contains(where: { $0.id == capsKey.id }) { self.recordedKeys.append(capsKey); self.recordedKeys.sort { $0.isModifier && !$1.isModifier } }
                }
                return nil
            }

            let keyCombinationForShortcut = self.activeKeys.union([logicalCapsLockKey])
            let downResult = handleKeyDown(for: logicalCapsLockKey, with: keyCombinationForShortcut)
            if capsOn { activeNormalKeys.insert(logicalCapsLockKey) } else { activeNormalKeys.remove(logicalCapsLockKey) }
            let upResult = handleKeyUp(for: logicalCapsLockKey, with: keyCombinationForShortcut)

            if downResult || upResult { return nil }
            else { return Unmanaged.passUnretained(event) }
        }
        
        let previousActiveKeys = activeKeys
        
        switch type {
        case .keyDown:
            activeNormalKeys.insert(keyCode)
        case .keyUp:
            activeNormalKeys.remove(keyCode)
        case .flagsChanged:
            let flags = event.flags
            if [55, 54].contains(keyCode) { if flags.contains(.maskCommand) { activeNormalKeys.insert(keyCode) } else { activeNormalKeys.remove(keyCode) } }
            else if [58, 61].contains(keyCode) { if flags.contains(.maskAlternate) { activeNormalKeys.insert(keyCode) } else { activeNormalKeys.remove(keyCode) } }
            else if [56, 60].contains(keyCode) { if flags.contains(.maskShift) { activeNormalKeys.insert(keyCode) } else { activeNormalKeys.remove(keyCode) } }
            else if [59, 62].contains(keyCode) { if flags.contains(.maskControl) { activeNormalKeys.insert(keyCode) } else { activeNormalKeys.remove(keyCode) } }
            else if keyCode == 63 { if flags.contains(.maskSecondaryFn) { activeNormalKeys.insert(keyCode) } else { activeNormalKeys.remove(keyCode) } }
        default:
            // This case handles special keys like brightness, volume, etc.
            if type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
                let finalKeyCode = CGKeyCode((nsEvent.data1 & 0xFFFF0000) >> 16)
                if finalKeyCode == 4 { return nil }
                
                let mappedKeyCode = finalKeyCode + systemKeyOffset
                let keyState = (nsEvent.data1 & 0x0000FF00) >> 8 // 0x0A is key down, 0x0B is key up

                if keyState == 0x0A { // System Key Down
                    activeSystemKeys.insert(mappedKeyCode)
                    if handleKeyDown(for: mappedKeyCode, with: activeKeys) {
                        return nil
                    }
                } else { // System Key Up
                    let previousActiveKeys = self.activeKeys
                    activeSystemKeys.remove(mappedKeyCode)
                    if handleKeyUp(for: mappedKeyCode, with: previousActiveKeys) {
                        return nil
                    }
                }
            }
        }
        
        if recordingState != nil {
            let isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            if case .appAssigning = recordingState { handleRecording(); return nil }
            else if isFrontmost { handleRecording(); return nil }
        }
        
        if type == .keyDown {
            if handleKeyDown(for: keyCode, with: activeKeys) {
                return nil
            }
        } else if type == .keyUp {
            if handleKeyUp(for: keyCode, with: previousActiveKeys) {
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func updateHotkeyCache() {
        hotkeyCache.removeAll()
        var allAssignments = settings.currentProfile.wrappedValue.assignments
        
        let quickAssignAssignment = Assignment(
            id: UUID(),
            shortcut: settings.appAssigningShortcut.keys,
            trigger: settings.appAssigningShortcut.trigger,
            configuration: .init(target: .app(name: "Quick Assign", bundleId: InternalShortcutID.quickAssign.rawValue))
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
                NotificationCenter.default.post(name: .cheatsheetKeyDown, object: nil)
                NotificationCenter.default.post(name: .showCheatsheet, object: nil)
            }
            return true
        }

        guard let assignments = hotkeyCache[comboId], !assignments.isEmpty else {
            return false
        }
        
        if pressTracker[comboId] != nil {
            return true
        }

        var info = PressInfo()
        
        let holdAssignments = assignments.filter({ $0.trigger == .hold })
        if !holdAssignments.isEmpty {
            let timer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
                guard let self = self, self.activeKeys == keyCombination else {
                    if let self { self.pressTracker[comboId]?.holdActionFired = false }
                    return
                }
                
                for assignment in holdAssignments {
                    _ = self.handleActivation(assignment: assignment)
                }
                self.pressTracker[comboId]?.holdActionFired = true
            }
            info.holdTimer = timer
        }
        
        pressTracker[comboId] = info
        
        return true
    }
    
    private func handleKeyUp(for triggerKey: CGKeyCode, with keyCombination: Set<CGKeyCode>) -> Bool {
        let comboId = keyCombination.map { String($0) }.sorted().joined(separator: "-")
        let cheatsheetComboId = settings.cheatsheetShortcut.keys.map { String($0.keyCode) }.sorted().joined(separator: "-")

        if !cheatsheetComboId.isEmpty && comboId == cheatsheetComboId {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cheatsheetKeyUp, object: nil)
                NotificationCenter.default.post(name: .hideCheatsheet, object: nil)
            }
            return true
        }

        guard var info = pressTracker[comboId] else {
            return hotkeyCache[comboId] != nil
        }

        info.holdTimer?.invalidate()
        info.holdTimer = nil
        
        if info.holdActionFired {
            pressTracker[comboId] = nil
            return true
        }
        
        info.dispatchWorkItem?.cancel()
        
        let now = CACurrentMediaTime()
        
        if (now - info.lastPressTime) > multiPressThreshold {
            info.count = 0
        }
        
        info.count += 1
        let currentCount = info.count
        info.lastPressTime = now
        
        guard let assignments = hotkeyCache[comboId] else {
            pressTracker[comboId] = nil
            return false
        }
                
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
            
            if let type = triggerType, let assignment = assignments.first(where: { $0.trigger == type }) {
                _ = self.handleActivation(assignment: assignment)
            }
            self.pressTracker[comboId] = nil
        }
        
        info.dispatchWorkItem = workItem
        pressTracker[comboId] = info
        DispatchQueue.main.asyncAfter(deadline: .now() + multiPressThreshold, execute: workItem)
        
        return true
    }
    
    private func pasteSnippet(_ content: String) {
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        
        let source = CGEventSource(stateID: .hidSystemState)
        let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        
        keyVDown?.flags = .maskCommand
        keyVUp?.flags = .maskCommand
        
        let loc = CGEventTapLocation.cgSessionEventTap
        keyVDown?.post(tap: loc)
        keyVUp?.post(tap: loc)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteboard.clearContents()
            if let original = originalContent {
                pasteboard.setString(original, forType: .string)
            }
        }
    }
    
    private func handleRecording() {
        DispatchQueue.main.async {
            let currentActiveKeys = self.activeKeys

            if !currentActiveKeys.isEmpty {
                if self.hasCapturedChord {
                    self.recordedKeys = []
                    self.hasCapturedChord = false
                }

                let newKeys = currentActiveKeys.map { kc -> ShortcutKey in
                    let isSystem = self.activeSystemKeys.contains(kc)
                    return ShortcutKey.from(keyCode: kc, isModifier: self.isModifierKeyCode(kc), isSystemEvent: isSystem)
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
            case .quickAssign:
                let shortcut = self.settings.appAssigningShortcut
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
            if case .cheatsheet = state, !hasKeys {
            } else if case .quickAssign = state, !hasKeys {
            } else {
                guard keysChanged || triggerChanged else { closeRecorder(); return }
            }
        }
        
        switch state {
        case .create(let target):
            let newAssignment = Assignment(shortcut: finalKeys, trigger: self.recordedTriggerType, configuration: .init(target:target))
            settings.addAssignment(newAssignment)
            NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "Shortcut for \(target.displayName) is now \(shortcutKeyCombinationString(for: finalKeys)).")
        case .edit(let id, let target):
            settings.updateAssignment(id: id, newShortcut: finalKeys, newTrigger: self.recordedTriggerType)
            NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "Shortcut for \(target.displayName) is now \(shortcutKeyCombinationString(for: finalKeys)).")
        case .cheatsheet:
            settings.cheatsheetShortcut = SpecialShortcut(keys: finalKeys, trigger: .press)
            NotificationManager.shared.sendNotification(title: "Cheatsheet Shortcut Set!", body: "The cheatsheet hotkey is now \(shortcutKeyCombinationString(for: finalKeys)).")
        case .quickAssign:
            settings.appAssigningShortcut = SpecialShortcut(keys: finalKeys, trigger: self.recordedTriggerType)
            NotificationManager.shared.sendNotification(title: "Quick Assign Shortcut Set!", body: "The Quick Assign hotkey is now \(shortcutKeyCombinationString(for: finalKeys)).")
        case .appAssigning(let target):
            let newAssignment = Assignment(shortcut: finalKeys, trigger: self.recordedTriggerType, configuration: .init(target:target))
            settings.addAssignment(newAssignment)
            NotificationManager.shared.sendNotification(title: "Shortcut Set!", body: "Shortcut for \(target.displayName) is now \(shortcutKeyCombinationString(for: finalKeys)).")
        }
        
        closeRecorder()
    }

    func clearRecordedShortcut() {
        guard let state = recordingState else { return }
        switch state {
        case .create(let target):
            let newAssignment = Assignment(shortcut: [], configuration: .init(target: target))
            settings.addAssignment(newAssignment)
            NotificationManager.shared.sendNotification(title: "Shortcut Added", body: "\(target.displayName) was added without a hotkey.")
        case .edit(let id, let target):
            settings.updateAssignment(id: id, newShortcut: [])
            NotificationManager.shared.sendNotification(title: "Shortcut Cleared", body: "The hotkey for \(target.displayName) has been removed.")
        case .cheatsheet:
            settings.cheatsheetShortcut = SpecialShortcut(keys: [], trigger: .press)
            NotificationManager.shared.sendNotification(title: "Cheatsheet Shortcut Cleared", body: "The hotkey for the cheatsheet has been removed.")
        case .quickAssign:
            settings.appAssigningShortcut = SpecialShortcut(keys: [], trigger: .press)
            NotificationManager.shared.sendNotification(title: "Quick Assign Shortcut Cleared", body: "The hotkey for Quick Assign has been removed.")
        case .appAssigning:
            closeRecorder()
        }
        closeRecorder()
    }

    func handleActivation(assignment: Assignment) -> Bool {
        guard let bundleId = assignment.configuration.target.bundleId else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .shortcutActivated, object: nil) }
            
            let config = assignment.configuration
            switch config.target {
            case .app(_, let bundleId): self.handleAppActivation(bundleId: bundleId, behavior: config.behavior)
            case .url(_, let address): DispatchQueue.main.async { if let url = URL(string: address) { NSWorkspace.shared.open(url) } }
            case .file(_, let path): DispatchQueue.main.async { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            case .script(_, let command, let runsInTerminal): DispatchQueue.global(qos: .userInitiated).async { self.runScript(command: command, runsInTerminal: runsInTerminal) }
            case .shortcut(_, let name): DispatchQueue.global(qos: .userInitiated).async { self.runShortcut(name: name) }
            case .snippet(_, let content):
                DispatchQueue.main.async {
                    NSApp.hide(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.pasteSnippet(content)
                    }
                }
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
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .shortcutActivated, object: nil)
                if self.recordingState != nil {
                    self.cancelRecording()
                    return
                }
                
                guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
                      let id = frontmostApp.bundleIdentifier else {
                    return
                }
                
                let appName = self.getAppName(for: id)
                self.startRecording(for: .appAssigning(target: .app(name: appName, bundleId: id)))
                NotificationCenter.default.post(name: .showAssigningOverlay, object: nil)
            }
            return true
        case .none:
            DispatchQueue.main.async { NotificationCenter.default.post(name: .shortcutActivated, object: nil) }
            handleAppActivation(bundleId: bundleId, behavior: assignment.configuration.behavior)
            return true
        }
    }

    // MARK: - App Activation Logic
    
    private func activateOrHide(app: NSRunningApplication) {
        DispatchQueue.global(qos: .userInitiated).async {
            let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
            if app.isActive {
                print("ACTION: App '\(appName)' is currently active. Hiding it.")
                DispatchQueue.main.async { app.hide() }
            } else {
                print("ACTION: App '\(appName)' is running in the background. Activating it.")
                
                if !self.hasScreenRecordingPermissions {
                    print("Enhanced switching disabled. Using simple activation.")
                    DispatchQueue.main.async { app.activate(options: [.activateIgnoringOtherApps]) }
                    return
                }
                
                if let windowToFocus = WindowFocusManager.findWindow(for: app.processIdentifier) {
                    DispatchQueue.main.async {
                        windowToFocus.focus()
                    }
                } else {
                    print("Could not find a specific window for \(appName), using simple activation.")
                    DispatchQueue.main.async { app.activate(options: [.activateIgnoringOtherApps]) }
                }
            }
        }
    }
    
    private func cycleWindows(for app: NSRunningApplication) {
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
        print("ACTION: Cycling windows for app '\(appName)'.")
    }

    private func launchAndActivate(bundleId: String) {
        print("ACTION: App '\(bundleId)' is not running. Launching and activating it.")
        DispatchQueue.main.async {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - Finder-specific Logic
    
    private func reopenAndActivateFinder() {
        let source = """
        tell application "Finder"
            reopen
            activate
        end tell
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
            if let err = error {
                print("AppleScript Error activating Finder: \(err)")
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
            }
        }
    }

    private func handleFinderActivation() {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            launchAndActivate(bundleId: "com.apple.finder")
            return
        }

        let isFinderFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"

        if !isFinderFrontmost {
            print("ACTION: Finder is not frontmost. Activating.")
            reopenAndActivateFinder()
            return
        }
        
        // --- THE FINAL FIX: Ask for VISIBLE windows ---
        let windowListScript = "tell application \"Finder\" to get every window whose visible is true"
        
        var windowCount = 0
        if let script = NSAppleScript(source: windowListScript) {
            var executionError: NSDictionary?
            let result = script.executeAndReturnError(&executionError)

            if executionError == nil {
                // The result of `get every window` is a list descriptor. We check its count.
                windowCount = result.numberOfItems
            } else {
                // If the script fails (e.g., permissions), we need a safe fallback.
                // Since Finder is already frontmost, hiding is the most intuitive action.
                print("ACTION: Finder is frontmost, but window check failed. Hiding as fallback.")
                finder.hide()
                return
            }
        }
        
        if windowCount > 0 {
            // Frontmost with visible windows -> Hide it.
            print("ACTION: Finder is frontmost with \(windowCount) visible window(s). Hiding.")
            finder.hide()
        } else {
            // Frontmost but no visible windows (only the desktop) -> Open a new one.
            print("ACTION: Finder is frontmost with no visible windows. Reopening.")
            reopenAndActivateFinder()
        }
    }

    private func handleAppActivation(bundleId: String, behavior: ShortcutConfiguration.Behavior) {
        if bundleId == "com.apple.finder" && behavior == .activateOrHide {
            handleFinderActivation()
            return
        }
        
        if let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            switch behavior {
            case .activateOrHide:
                activateOrHide(app: targetApp)
            case .cycleWindows:
                cycleWindows(for: targetApp)
            }
        } else {
            launchAndActivate(bundleId: bundleId)
        }
    }
    
    private func hotkeyIdentifier(for keys: [ShortcutKey], trigger: ShortcutTriggerType) -> String {
        let sortedKeyCodes = keys.map { String($0.keyCode) }.sorted()
        return sortedKeyCodes.joined(separator: "-") + "-\(trigger.rawValue)"
    }

    private func checkForConflicts() {
        var hotkeys: [String: [ConflictableIdentifier]] = [:]
        
        for assignment in settings.currentProfile.wrappedValue.assignments where !assignment.shortcut.isEmpty {
            let id = hotkeyIdentifier(for: assignment.shortcut, trigger: assignment.trigger)
            hotkeys[id, default: []].append(.assignment(id: assignment.id))
        }

        if !settings.cheatsheetShortcut.keys.isEmpty {
            let id = hotkeyIdentifier(for: settings.cheatsheetShortcut.keys, trigger: settings.cheatsheetShortcut.trigger)
            hotkeys[id, default: []].append(.cheatsheet)
        }
        
        if !settings.appAssigningShortcut.keys.isEmpty {
            let id = hotkeyIdentifier(for: settings.appAssigningShortcut.keys, trigger: settings.appAssigningShortcut.trigger)
            hotkeys[id, default: []].append(.quickAssign)
        }
        
        var allConflictingIds = Set<String>()
        for (_, identifiers) in hotkeys where identifiers.count > 1 {
            for identifier in identifiers {
                allConflictingIds.insert(identifier.stringValue)
            }
        }

        self.conflictingAssignmentIDs = Set(allConflictingIds.compactMap { UUID(uuidString: $0) })
        self.isCheatsheetConflicting = allConflictingIds.contains(ConflictableIdentifier.cheatsheet.stringValue)
        self.isQuickAssignConflicting = allConflictingIds.contains(ConflictableIdentifier.quickAssign.stringValue)
    }
    
    private func runScript(command: String, runsInTerminal: Bool) {
        if runsInTerminal {
            let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let appleScriptSource = """
            tell application "Terminal"
            activate
            do script "\(escapedCommand)"
            end tell
            """
            var error: NSDictionary?
            if let script = NSAppleScript(source: appleScriptSource) {
                script.executeAndReturnError(&error)
                if let err = error {
                    print("AppleScript Error: \(err)")
                }
            }
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", command]
            do {
                try task.run()
            } catch {
                print("Failed to run script in background: \(error)")
            }
        }
    }
    
    private func runShortcut(name: String) { let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); task.arguments = ["run", name]; do { try task.run() } catch { print("Failed to run shortcut '\(name)': \(error)"); NotificationManager.shared.sendNotification(title: "Shortcut Failed", body: "Could not run '\(name)'.") } }
    
    func getAppName(for bundleId: String) -> String {
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
    
    func shortcutKeyCombinationString(for keys: [ShortcutKey]) -> String { if keys.isEmpty { return "Not Set" }; return keys.map { $0.symbol }.joined(separator: " + ") }
}

fileprivate extension ShortcutTarget {
    var bundleId: String? {
        if case .app(_, let id) = self {
            return id
        }
        return nil
    }
}


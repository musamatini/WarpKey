import AppKit
import Foundation
import UserNotifications
import CoreGraphics
import Carbon.HIToolbox

// MARK: - Notifications
extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
    static let goToHelpPageInMainWindow = Notification.Name("goToHelpPageInMainWindow")
    static let shortcutActivated = Notification.Name("shortcutActivated")
    static let requestAppRestart = Notification.Name("requestAppRestart")
    static let showCheatsheet = Notification.Name("showCheatsheet")
    static let hideCheatsheet = Notification.Name("hideCheatsheet")
}

// MARK: - Accessibility
struct AccessibilityManager {
    static func checkPermissions() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }

    static func requestPermissions() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
}

// MARK: - Notification Manager
class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    
    private let assignmentCategoryIdentifier = "ASSIGNMENT_CATEGORY"
    private let updateCategoryIdentifier = "UPDATE_AVAILABLE_CATEGORY"
    
    private init() {
        registerNotificationCategories()
    }

    func requestUserPermission(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
    
    private func registerNotificationCategories() {
        let openAction = UNNotificationAction(identifier: "OPEN_ACTION", title: "Open App", options: [.foreground])
        let assignmentCategory = UNNotificationCategory(identifier: assignmentCategoryIdentifier, actions: [openAction], intentIdentifiers: [], options: [])
        
        let updateAction = UNNotificationAction(identifier: "UPDATE_ACTION", title: "Install Update", options: [.foreground])
        let updateCategory = UNNotificationCategory(identifier: updateCategoryIdentifier, actions: [updateAction], intentIdentifiers: [], options: [])
        
        center.setNotificationCategories([assignmentCategory, updateCategory])
    }
    
    func sendAssignmentNotification(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Shortcut Assigned!"
        content.body = "A new shortcut was assigned to \(appName)."
        content.sound = .default
        content.categoryIdentifier = assignmentCategoryIdentifier
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
    
    func sendUpdateAvailableNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "A New WrapKey Version is Available!"
        content.body = "Version \(version) is ready to be installed."
        content.sound = .default
        content.categoryIdentifier = updateCategoryIdentifier
        
        let request = UNNotificationRequest(identifier: "SPARKLE_UPDATE_AVAILABLE", content: content, trigger: nil)
        center.add(request)
    }

    func sendNotification(title: String, body: String, delay: TimeInterval = 0) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = delay > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false) : nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        center.add(request)
    }
}

// MARK: - Shortcut Runner
struct ShortcutRunner {
    static func getAllShortcutNames(completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            task.arguments = ["list"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                
                if let output = String(data: data, encoding: .utf8) {
                    let names = output.split(whereSeparator: \.isNewline).map(String.init)
                    DispatchQueue.main.async {
                        completion(names)
                    }
                } else {
                    DispatchQueue.main.async { completion([]) }
                }
            } catch {
                print("Failed to get shortcuts list: \(error)")
                DispatchQueue.main.async { completion([]) }
            }
        }
    }
}

// MARK: - Keyboard Layout
struct KeyboardLayout {
    
    private static let systemKeyNames: [CGKeyCode: String] = [
        2: "Brightness Up",
        3: "Brightness Down",
        7: "Mute",
        16: "Play/Pause",
        19: "Next Track",
        20: "Previous Track",
        160: "Mission Control",
        176: "Dictation/Siri",
        177: "Spotlight",
        178: "Focus"
    ]
    
    private static let specialKeyNames: [CGKeyCode: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Esc",
        57: "Caps Lock",
        71: "Help",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        109: "F10",
        111: "F12",
        115: "Home",
        116: "Page Up",
        117: "Fwd Del",
        118: "F4",
        119: "End",
        120: "F2",
        121: "Page Down",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
        50: "`",
        39: "'",
        300: "Caps Lock"
    ]
    
    static func character(for keyCode: CGKeyCode, isSystemEvent: Bool) -> String? {
        if keyCode == 300 {
            return "Caps Lock"
        }
        
        if isSystemEvent {
            return systemKeyNames[keyCode]
        } else {
            if let specialName = specialKeyNames[keyCode] {
                return specialName
            }
            if let char = getCharFromKeyCode(keyCode) {
                return char
            }
        }
        return nil
    }
    
    private static func getCharFromKeyCode(_ keyCode: CGKeyCode) -> String? {
        if keyCode == 300 {
            return "Caps Lock"
        }
        
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = unsafeBitCast(layoutData, to: CFData.self) as Data
        
        return data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> String? in
            guard let layout = pointer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var actualChars = 0
            var unicodeChars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()), 0, &deadKeyState, unicodeChars.count, &actualChars, &unicodeChars)
            if status == noErr && actualChars > 0 {
                let charString = String(utf16CodeUnits: &unicodeChars, count: actualChars)
                if charString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return nil
                }
                return charString.uppercased()
            }
            return nil
        }
    }
}


// MARK: - Appearance
extension NSAppearance {
    var isDark: Bool {
        if bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return true
        }
        return false
    }
}

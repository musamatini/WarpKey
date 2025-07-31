//Utils.swift
import AppKit
import Foundation
import UserNotifications
import CoreGraphics
import Carbon.HIToolbox

// MARK: - Notifications
extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
    static let goToHelpPageInMainWindow = Notification.Name("goToHelpPageInMainWindow")
    static let keyPressEvent = Notification.Name("KeyPressEvent")
    static let shortcutActivated = Notification.Name("shortcutActivated")
    static let requestAppRestart = Notification.Name("requestAppRestart")
}

// MARK: - System Managers
struct AccessibilityManager {
    static func checkPermissions() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }

    static func requestPermissions() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
}

class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    
    // MARK: - Notification Category Identifiers
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
        // Category for new shortcut assignments
        let openAction = UNNotificationAction(identifier: "OPEN_ACTION", title: "Open App", options: [.foreground])
        let assignmentCategory = UNNotificationCategory(identifier: assignmentCategoryIdentifier, actions: [openAction], intentIdentifiers: [], options: [])
        
        // Category for available updates
        let updateAction = UNNotificationAction(identifier: "UPDATE_ACTION", title: "Install Update", options: [.foreground])
        let updateCategory = UNNotificationCategory(identifier: updateCategoryIdentifier, actions: [updateAction], intentIdentifiers: [], options: [])
        
        center.setNotificationCategories([assignmentCategory, updateCategory])
    }
    
    func sendAssignmentNotification(appName: String, keyString: String) {
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

// MARK: - System Utilities
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


// MARK: - Keyboard Utilities
struct KeyboardLayout {
    private static let specialKeyNames: [CGKeyCode: String] = [
        0x24: "Return",      0x30: "Tab",         0x31: "Space",
        0x33: "Delete",      0x35: "Escape",      0x39: "Caps Lock",
        0x7A: "F1",          0x78: "F2",          0x63: "F3",
        0x76: "F4",          0x60: "F5",          0x61: "F6",
        0x62: "F7",          0x64: "F8",          0x65: "F9",
        0x6D: "F10",         0x67: "F11",         0x6F: "F12",
        0x69: "F13",         0x6B: "F14",         0x71: "F15",
        0x6A: "F16",         0x40: "F17",         0x4F: "F18",
        0x50: "F19",
        0x72: "Help",        0x73: "Home",        0x74: "Page Up",
        0x75: "Forward Delete", 0x77: "End",      0x79: "Page Down",
        0x7B: "←",           0x7C: "→",           0x7D: "↓",
        0x7E: "↑"
    ]
    
    static func character(for keyCode: CGKeyCode) -> String? {
        if let specialName = specialKeyNames[keyCode] {
            return specialName
        }
        
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue(),
              let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        
        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self) as Data
        let layout = layoutData.withUnsafeBytes { $0.bindMemory(to: UCKeyboardLayout.self).baseAddress! }

        var deadKeyState: UInt32 = 0
        let maxChars = 4
        var actualChars = 0
        var unicodeChars = [UniChar](repeating: 0, count: maxChars)
        
        let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()), 0, &deadKeyState, maxChars, &actualChars, &unicodeChars)
        
        if status == noErr && actualChars > 0 {
            return String(utf16CodeUnits: unicodeChars, count: actualChars).uppercased()
        }
        
        return nil
    }
}

// MARK: - Appearance Utilities
extension NSAppearance {
    var isDark: Bool {
        if bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return true
        }
        return false
    }
}

// AccessibilityManager.swift

import AppKit
import Foundation

struct AccessibilityManager {

    static func checkPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        return isTrusted
    }

    static func requestPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    static func checkAndRequestPermissions() {
        if !checkPermissions() {
            print("[WARN] Accessibility permissions are not granted.")
            
            let alert = NSAlert()
            alert.messageText = "Accessibility Permissions Required"
            alert.informativeText = "To control other applications, WarpKey needs Accessibility permissions. Please grant access in System Settings."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                SystemSettingsManager.openAccessibilitySettings()
            }
        } else {
            print("[SUCCESS] Accessibility permissions are already granted.")
        }
    }
}

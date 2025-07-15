// SystemSettingsManager.swift

import AppKit
import Foundation

struct SystemSettingsManager {
    
    static func openAccessibilitySettings() {
        // This modern URL-based approach is generally better than AppleScript.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
             NSWorkspace.shared.open(url)
        }
    }
    
    static func openNotificationSettings() {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            print("[SystemSettings] CRITICAL: Could not get bundle identifier.")
            return
        }
        
        let urlString = "x-apple-systempreferences:com.apple.preference.notifications?id=\(bundleId)"
        print("[SystemSettings] Attempting to open URL: \(urlString)")
    
        if let url = URL(string: urlString) {
             NSWorkspace.shared.open(url)
        }
    }
}

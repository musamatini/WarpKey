// NotificationManager.swift

import AppKit
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    
    private init() {
        center.removeAllDeliveredNotifications()
        registerNotificationCategories()
    }

    func requestUserPermission(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("[Notifications] Permission granted")
                } else if let error = error {
                    print("[Notifications] Error requesting authorization: \(error.localizedDescription)")
                } else {
                    print("[Notifications] Permission denied by user")
                }
                completion(granted)
            }
        }
    }
    
    private func registerNotificationCategories() {
        let action = UNNotificationAction(
            identifier: "OPEN_ACTION",
            title: "Open App",
            options: [.foreground]
        )
        
        let category = UNNotificationCategory(
            identifier: "ASSIGNMENT_CATEGORY",
            actions: [action],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([category])
    }
    
    func sendAssignmentNotification(appName: String, keyString: String) {
        let content = UNMutableNotificationContent()
        content.title = "Shortcut Assigned!"
        content.body = "Right Command + \(keyString) now launches \(appName)."
        content.sound = .default
        content.categoryIdentifier = "ASSIGNMENT_CATEGORY"
        content.userInfo = ["appName": appName, "keyCombo": keyString]

        let request = UNNotificationRequest(
            identifier: "assignment-\(appName)-\(keyString)",
            content: content,
            trigger: nil
        )
        
        center.add(request) { error in
            if let error = error {
                print("[Notifications] Failed to send: \(error.localizedDescription)")
            } else {
                print("[Notifications] Assignment notification scheduled successfully.")
            }
        }
    }
    
    func sendNotification(title: String, body: String, delay: TimeInterval = 0) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let trigger = delay > 0 ? UNTimeIntervalNotificationTrigger(
            timeInterval: delay,
            repeats: false
        ) : nil
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        center.add(request) { error in
            if let error = error {
                print("[Notifications] Failed to send generic notification: \(error.localizedDescription)")
            }
        }
    }
    
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func checkAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }
}

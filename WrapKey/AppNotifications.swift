import Foundation

extension Notification.Name {
    /// Tells the AppDelegate to show or hide the menu bar icon based on user settings.
    static let toggleMenuBarIcon = Notification.Name("toggleMenuBarIcon")
    
    /// Tells the main window to appear (from a Dock or menu bar click).
    static let openMainWindow = Notification.Name("openMainWindow")
    
    // REMOVED: static let openWelcomeWindow as Welcome is now a tab/page within the main window

    /// Notification for when onboarding is completed, to transition from welcome to main window.
    static let openMainWindowOnboardingComplete = Notification.Name("openMainWindowOnboardingComplete")

    // ✅ NEW: Notification to open main window AND navigate directly to Help page.
    static let goToHelpPageInMainWindow = Notification.Name("goToHelpPageInMainWindow")
}

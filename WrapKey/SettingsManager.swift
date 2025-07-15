// SettingsManager.swift

import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    // Keys for UserDefaults. Using constants prevents typos.
    private let menuBarIconKey = "showMenuBarIcon_v1" // Added version to be safe
    private let onboardingKey = "hasCompletedOnboarding_v1" // Added version to be safe

    @Published var showMenuBarIcon: Bool {
        didSet {
            UserDefaults.standard.set(showMenuBarIcon, forKey: menuBarIconKey)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            // This is the ONLY place this value should be saved.
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey)
            print("[SettingsManager] 'hasCompletedOnboarding' was just set to: \(hasCompletedOnboarding). Saving to UserDefaults.")
        }
    }

    init() {
        // --- Initialization Phase ---
        // Load the value from storage. If it doesn't exist, .bool(forKey:) returns `false` by default.
        // This is the behavior we want for a first launch.
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        
        // Initialize the menu bar icon setting.
        if UserDefaults.standard.object(forKey: menuBarIconKey) == nil {
            self.showMenuBarIcon = true // Default to showing the icon on first launch
        } else {
            self.showMenuBarIcon = UserDefaults.standard.bool(forKey: menuBarIconKey)
        }

        // --- Debugging Phase ---
        // This log now runs AFTER everything is initialized.
        print("[SettingsManager] Initialized. Loaded value for 'hasCompletedOnboarding' is: \(self.hasCompletedOnboarding)")
    }
}

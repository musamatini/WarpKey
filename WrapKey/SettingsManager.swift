//SettingsManager.swift
import SwiftUI
import Combine

// MARK: - Data Models
enum ShortcutCategory: String, CaseIterable, Codable, Hashable, Identifiable {
    case app = "Apps"
    case shortcut = "Shortcuts"
    case url = "URLs"
    case file = "Files & Folders"
    case script = "Scripts"
    
    var id: String { self.rawValue }
    
    var systemImage: String {
        switch self {
        case .app: "square.grid.2x2.fill"
        case .url: "globe"
        case .file: "doc"
        case .script: "terminal"
        case .shortcut: "square.stack.3d.up.fill"
        }
    }
}

struct Assignment: Codable, Identifiable, Hashable {
    var id = UUID()
    var keyCode: CGKeyCode
    var configuration: ShortcutConfiguration
}

struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var triggerModifiers: [ShortcutCategory: ModifierKey]
    var secondaryModifier: ModifierKey
    var assignments: [Assignment]
}

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    // MARK: - Keys
    private let profilesKey = "WarpKey_Profiles_v4"
    private let currentProfileIDKey = "WarpKey_CurrentProfileID_v2"
    private let menuBarIconKey = "showMenuBarIcon_v1"
    private let onboardingKey = "hasCompletedOnboarding_v1"

    // MARK: - Published Properties
    @Published var profiles: [Profile] {
        didSet { saveProfiles() }
    }
    
    @Published var currentProfileID: UUID {
        didSet {
            UserDefaults.standard.set(currentProfileID.uuidString, forKey: currentProfileIDKey)
            objectWillChange.send()
        }
    }
    
    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: menuBarIconKey) }
    }
    
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey) }
    }
    
    var currentProfile: Binding<Profile> {
        Binding(
            get: {
                if let index = self.profiles.firstIndex(where: { $0.id == self.currentProfileID }) {
                    return self.profiles[index]
                }
                if !self.profiles.isEmpty { return self.profiles[0] }
                
                let defaultProfile = SettingsManager.createDefaultProfile()
                if self.profiles.isEmpty {
                    DispatchQueue.main.async {
                        self.profiles = [defaultProfile]
                        self.currentProfileID = defaultProfile.id
                    }
                }
                return defaultProfile
            },
            set: { updatedProfile in
                if let index = self.profiles.firstIndex(where: { $0.id == updatedProfile.id }) {
                    self.profiles[index] = updatedProfile
                }
            }
        )
    }

    // MARK: - Initialization
    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        if UserDefaults.standard.object(forKey: menuBarIconKey) == nil {
            self.showMenuBarIcon = true
        } else {
            self.showMenuBarIcon = UserDefaults.standard.bool(forKey: menuBarIconKey)
        }

        let loadedProfiles: [Profile]
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decodedProfiles = try? JSONDecoder().decode([Profile].self, from: data),
           !decodedProfiles.isEmpty {
            loadedProfiles = decodedProfiles.map { profile in
                var migratedProfile = profile
                for category in ShortcutCategory.allCases {
                    if migratedProfile.triggerModifiers[category] == nil {
                        migratedProfile.triggerModifiers[category] = migratedProfile.triggerModifiers[.app] ?? ModifierKey.from(keyCode: 54)
                    }
                }
                return migratedProfile
            }
        } else {
            UserDefaults.standard.removeObject(forKey: "WarpKey_Profiles_v3")
            loadedProfiles = [SettingsManager.createDefaultProfile()]
        }
        
        self.profiles = loadedProfiles
        
        if let uuidString = UserDefaults.standard.string(forKey: currentProfileIDKey),
           let uuid = UUID(uuidString: uuidString),
           loadedProfiles.contains(where: { $0.id == uuid }) {
            self.currentProfileID = uuid
        } else {
            self.currentProfileID = loadedProfiles.first!.id
        }
    }
    
    private static func createDefaultProfile() -> Profile {
        let defaultTrigger = ModifierKey.from(keyCode: 54)
        var triggers: [ShortcutCategory: ModifierKey] = [:]
        for category in ShortcutCategory.allCases {
            triggers[category] = defaultTrigger
        }
        
        return Profile(
            name: "Default",
            triggerModifiers: triggers,
            secondaryModifier: ModifierKey.from(keyCode: 61),
            assignments: []
        )
    }
    
    // MARK: - Public Methods
    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }
    }
    
    func addAssignment(_ assignment: Assignment) {
        if let index = self.profiles.firstIndex(where: { $0.id == self.currentProfileID }) {
            profiles[index].assignments.append(assignment)
        }
    }
    
    func updateAssignment(id: UUID, newKeyCode: CGKeyCode) {
        if let profileIndex = self.profiles.firstIndex(where: { $0.id == self.currentProfileID }),
           let assignmentIndex = self.profiles[profileIndex].assignments.firstIndex(where: { $0.id == id }) {
            self.profiles[profileIndex].assignments[assignmentIndex].keyCode = newKeyCode
        }
    }
    
    // Important: New method to update the content of a shortcut
    func updateAssignmentContent(id: UUID, newTarget: ShortcutTarget) {
        if let profileIndex = self.profiles.firstIndex(where: { $0.id == self.currentProfileID }),
           let assignmentIndex = self.profiles[profileIndex].assignments.firstIndex(where: { $0.id == id }) {
            self.profiles[profileIndex].assignments[assignmentIndex].configuration.target = newTarget
        }
    }
    
    func addNewProfile(name: String) {
        let newProfile = Profile(
            name: name,
            triggerModifiers: self.currentProfile.wrappedValue.triggerModifiers,
            secondaryModifier: self.currentProfile.wrappedValue.secondaryModifier,
            assignments: []
        )
        profiles.append(newProfile)
        currentProfileID = newProfile.id
    }
    
    func deleteProfile(id: UUID) {
        guard profiles.count > 1 else { return }
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles.remove(at: index)
            if currentProfileID == id {
                currentProfileID = profiles.first!.id
            }
        }
    }
    
    func triggerModifier(for target: ShortcutTarget) -> ModifierKey {
        let category = target.category
        return self.currentProfile.wrappedValue.triggerModifiers[category]!
    }
}

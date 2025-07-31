//SettingsManager.swift
import SwiftUI
import Combine

// MARK: - Data Models
enum ColorSchemeSetting: String, Codable, CaseIterable {
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"
}

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
    var keyCode: CGKeyCode?
    var configuration: ShortcutConfiguration
}

struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var triggerModifiers: [ShortcutCategory: [ModifierKey]]
    var secondaryModifier: [ModifierKey]
    var assignments: [Assignment]
}

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    // MARK: - Keys
    private let profilesKey = "WrapKey_Profiles_v5"
    private let currentProfileIDKey = "WrapKey_CurrentProfileID_v2"
    private let menuBarIconKey = "showMenuBarIcon_v1"
    private let onboardingKey = "hasCompletedOnboarding_v1"
    private let colorSchemeKey = "WrapKey_ColorScheme_v1"

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
    
    @Published var colorScheme: ColorSchemeSetting {
        didSet { UserDefaults.standard.set(colorScheme.rawValue, forKey: colorSchemeKey) }
    }
    
    @Published private(set) var systemColorScheme: ColorScheme = .light
    
    private var appearanceCancellable: AnyCancellable?
    
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

        if let rawValue = UserDefaults.standard.string(forKey: colorSchemeKey),
           let scheme = ColorSchemeSetting(rawValue: rawValue) {
            self.colorScheme = scheme
        } else {
            self.colorScheme = .auto
        }

        let loadedProfiles = SettingsManager.loadAndMigrateProfiles(from: profilesKey)
        self.profiles = loadedProfiles
        
        if let uuidString = UserDefaults.standard.string(forKey: currentProfileIDKey),
           let uuid = UUID(uuidString: uuidString),
           loadedProfiles.contains(where: { $0.id == uuid }) {
            self.currentProfileID = uuid
        } else {
            self.currentProfileID = loadedProfiles.first!.id
        }
    }
    
    func setupAppearanceMonitoring() {
        self.systemColorScheme = NSApp.effectiveAppearance.isDark ? .dark : .light
        appearanceCancellable = NSApp.publisher(for: \.effectiveAppearance)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] appearance in
                self?.systemColorScheme = appearance.isDark ? .dark : .light
            }
    }
    
    private static func loadAndMigrateProfiles(from key: String) -> [Profile] {
        let oldProfilesKeyV4 = "WrapKey_Profiles_v4"
        let oldProfilesKeyV3 = "WrapKey_Profiles_v3"
        
        if let data = UserDefaults.standard.data(forKey: key),
           let decodedProfiles = try? JSONDecoder().decode([Profile].self, from: data),
           !decodedProfiles.isEmpty {
            return decodedProfiles
        }
        
        if let oldData = UserDefaults.standard.data(forKey: oldProfilesKeyV4) {
            struct OldAssignmentV4: Codable { var id: UUID; var keyCode: CGKeyCode; var configuration: ShortcutConfiguration }
            struct OldProfileV4: Codable {
                var id: UUID; var name: String; var triggerModifiers: [ShortcutCategory: ModifierKey]
                var secondaryModifier: ModifierKey; var assignments: [OldAssignmentV4]
            }
            if let decodedOldProfiles = try? JSONDecoder().decode([OldProfileV4].self, from: oldData) {
                let migrated = decodedOldProfiles.map { old -> Profile in
                    var newTriggers = old.triggerModifiers.mapValues { [$0] }
                    for category in ShortcutCategory.allCases where newTriggers[category] == nil {
                        newTriggers[category] = newTriggers[.app] ?? [ModifierKey.from(keyCode: 54)]
                    }
                    let newAssignments = old.assignments.map { oldA in
                        Assignment(id: oldA.id, keyCode: oldA.keyCode, configuration: oldA.configuration)
                    }
                    return Profile(id: old.id, name: old.name, triggerModifiers: newTriggers, secondaryModifier: [old.secondaryModifier], assignments: newAssignments)
                }
                UserDefaults.standard.removeObject(forKey: oldProfilesKeyV4)
                print("[Migration] Successfully migrated profiles from v4 to v5.")
                return migrated
            }
        }
        
        UserDefaults.standard.removeObject(forKey: oldProfilesKeyV3)
        
        return [createDefaultProfile()]
    }
    
    private static func createDefaultProfile() -> Profile {
        let defaultTrigger = [ModifierKey.from(keyCode: 54)]
        var triggers: [ShortcutCategory: [ModifierKey]] = [:]
        for category in ShortcutCategory.allCases {
            triggers[category] = defaultTrigger
        }
        
        return Profile(
            name: "Default",
            triggerModifiers: triggers,
            secondaryModifier: [ModifierKey.from(keyCode: 61)],
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
        currentProfile.wrappedValue.assignments.append(assignment)
    }
    
    func updateAssignment(id: UUID, newKeyCode: CGKeyCode?) {
        if let assignmentIndex = currentProfile.wrappedValue.assignments.firstIndex(where: { $0.id == id }) {
            currentProfile.wrappedValue.assignments[assignmentIndex].keyCode = newKeyCode
        }
    }
    
    func updateAssignmentContent(id: UUID, newTarget: ShortcutTarget) {
        if let assignmentIndex = currentProfile.wrappedValue.assignments.firstIndex(where: { $0.id == id }) {
            currentProfile.wrappedValue.assignments[assignmentIndex].configuration.target = newTarget
        }
    }
    
    func addModifierKey(_ newKey: ModifierKey, for category: ShortcutCategory, type: ModifierType) {
        if type == .trigger {
            currentProfile.wrappedValue.triggerModifiers[category]?.append(newKey)
        } else {
            currentProfile.wrappedValue.secondaryModifier.append(newKey)
        }
    }
    
    func removeModifierKey(_ keyToRemove: ModifierKey, for category: ShortcutCategory, type: ModifierType) {
        if type == .trigger {
            currentProfile.wrappedValue.triggerModifiers[category]?.removeAll(where: { $0.keyCode == keyToRemove.keyCode })
        } else {
            currentProfile.wrappedValue.secondaryModifier.removeAll(where: { $0.keyCode == keyToRemove.keyCode })
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
    
    func triggerModifiers(for target: ShortcutTarget) -> [ModifierKey] {
        let category = target.category
        return self.currentProfile.wrappedValue.triggerModifiers[category] ?? []
    }
}

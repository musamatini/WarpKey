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
    var shortcut: [ShortcutKey]
    var configuration: ShortcutConfiguration
}

struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var assignments: [Assignment]
}

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    // MARK: - Keys
    private let profilesKey = "WrapKey_Profiles_v6"
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
                if let firstProfile = self.profiles.first {
                    DispatchQueue.main.async { self.currentProfileID = firstProfile.id }
                    return firstProfile
                }
                
                let defaultProfile = SettingsManager.createDefaultProfile()
                DispatchQueue.main.async {
                    self.profiles = [defaultProfile]
                    self.currentProfileID = defaultProfile.id
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
        self.showMenuBarIcon = UserDefaults.standard.object(forKey: menuBarIconKey) == nil ? true : UserDefaults.standard.bool(forKey: menuBarIconKey)

        if let rawValue = UserDefaults.standard.string(forKey: colorSchemeKey), let scheme = ColorSchemeSetting(rawValue: rawValue) {
            self.colorScheme = scheme
        } else {
            self.colorScheme = .auto
        }

        let loadedProfiles = SettingsManager.loadAndMigrateProfiles(from: profilesKey)
        self.profiles = loadedProfiles
        
        if let uuidString = UserDefaults.standard.string(forKey: currentProfileIDKey), let uuid = UUID(uuidString: uuidString), loadedProfiles.contains(where: { $0.id == uuid }) {
            self.currentProfileID = uuid
        } else {
            self.currentProfileID = loadedProfiles.first?.id ?? SettingsManager.createDefaultProfile().id
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
        if let data = UserDefaults.standard.data(forKey: key),
           let decodedProfiles = try? JSONDecoder().decode([Profile].self, from: data),
           !decodedProfiles.isEmpty {
            return decodedProfiles
        }
        
        let oldProfilesKeyV5 = "WrapKey_Profiles_v5"
        if let oldData = UserDefaults.standard.data(forKey: oldProfilesKeyV5) {
            struct OldShortcutKey: Codable { var keyCode: CGKeyCode; var isTrueModifier: Bool }
            struct OldAssignmentV5: Codable { var id: UUID; var keyCode: CGKeyCode?; var configuration: ShortcutConfiguration }
            struct OldProfileV5: Codable {
                var id: UUID; var name: String; var triggerModifiers: [ShortcutCategory: [OldShortcutKey]];
                var secondaryModifier: [OldShortcutKey]; var assignments: [OldAssignmentV5]
            }

            if let decodedOldProfiles = try? JSONDecoder().decode([OldProfileV5].self, from: oldData) {
                let migratedProfiles = decodedOldProfiles.map { oldProfile -> Profile in
                    let newAssignments = oldProfile.assignments.map { oldAssignment -> Assignment in
                        var newShortcut: [ShortcutKey] = []
                        let category = oldAssignment.configuration.target.category
                        
                        // Use only the category-specific trigger modifiers from the old version.
                        // The global `secondaryModifier` is now ignored entirely.
                        let modifiersToApply = oldProfile.triggerModifiers[category] ?? []
                        
                        newShortcut.append(contentsOf: modifiersToApply.map { oldKey in
                            return ShortcutKey.from(keyCode: oldKey.keyCode, isModifier: oldKey.isTrueModifier)
                        })
                        
                        if let kc = oldAssignment.keyCode {
                            newShortcut.append(ShortcutKey.from(keyCode: kc, isModifier: false))
                        }
                        
                        return Assignment(id: oldAssignment.id, shortcut: newShortcut, configuration: oldAssignment.configuration)
                    }
                    return Profile(id: oldProfile.id, name: oldProfile.name, assignments: newAssignments)
                }
                
                UserDefaults.standard.removeObject(forKey: oldProfilesKeyV5)
                if let encoded = try? JSONEncoder().encode(migratedProfiles) {
                    UserDefaults.standard.set(encoded, forKey: key)
                }
                return migratedProfiles
            }
        }
        
        return [createDefaultProfile()]
    }
    
    private static func createDefaultProfile() -> Profile {
        return Profile(name: "Default", assignments: [])
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
    
    func updateAssignment(id: UUID, newShortcut: [ShortcutKey]) {
        if let index = currentProfile.wrappedValue.assignments.firstIndex(where: { $0.id == id }) {
            currentProfile.wrappedValue.assignments[index].shortcut = newShortcut
        }
    }
    
    func updateAssignmentContent(id: UUID, newTarget: ShortcutTarget) {
        if let index = currentProfile.wrappedValue.assignments.firstIndex(where: { $0.id == id }) {
            currentProfile.wrappedValue.assignments[index].configuration.target = newTarget
        }
    }
    
    func addNewProfile(name: String) {
        let newProfile = Profile(name: name, assignments: [])
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
}

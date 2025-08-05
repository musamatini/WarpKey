// SettingsManager.swift
import SwiftUI
import Combine

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

enum ShortcutTriggerType: String, Codable, CaseIterable, Hashable, Identifiable {
    case press = "Press"
    case doublePress = "Double Press"
    case triplePress = "Triple Press"
    case hold = "Hold"
    
    var id: String { self.rawValue }
    
    var abbreviation: String {
        switch self {
        case .press: return ""
        case .doublePress: return "DP"
        case .triplePress: return "TP"
        case .hold: return "Hold"
        }
    }
}

struct SpecialShortcut: Codable, Hashable {
    var keys: [ShortcutKey]
    var trigger: ShortcutTriggerType
}

struct Assignment: Codable, Identifiable, Hashable {
    var id = UUID()
    var shortcut: [ShortcutKey]
    var trigger: ShortcutTriggerType
    var configuration: ShortcutConfiguration
    
    init(id: UUID = UUID(), shortcut: [ShortcutKey], trigger: ShortcutTriggerType = .press, configuration: ShortcutConfiguration) {
        self.id = id
        self.shortcut = shortcut
        self.trigger = trigger
        self.configuration = configuration
    }
    
    enum CodingKeys: String, CodingKey {
        case id, shortcut, trigger, configuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        shortcut = try container.decode([ShortcutKey].self, forKey: .shortcut)
        trigger = try container.decodeIfPresent(ShortcutTriggerType.self, forKey: .trigger) ?? .press
        configuration = try container.decode(ShortcutConfiguration.self, forKey: .configuration)
    }
}

struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var assignments: [Assignment]
}

class SettingsManager: ObservableObject {
    private let profilesKey = "WrapKey_Profiles_v6"
    private let currentProfileIDKey = "WrapKey_CurrentProfileID_v2"
    private let menuBarIconKey = "showMenuBarIcon_v1"
    private let onboardingKey = "hasCompletedOnboarding_v1"
    private let colorSchemeKey = "WrapKey_ColorScheme_v1"
    private let appThemeKey = "WrapKey_AppTheme_v1"
    private let cheatsheetShortcutKey = "WrapKey_CheatsheetShortcut_v2"
    private let appAssigningShortcutKey = "WrapKey_AppAssigningShortcut_v2"

    private let oldCheatsheetShortcutKey = "WrapKey_CheatsheetShortcut_v1"
    private let oldAppAssigningShortcutKey = "WrapKey_AppAssigningShortcut_v1"

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

    @Published var appTheme: Theme {
        didSet { UserDefaults.standard.set(appTheme.rawValue, forKey: appThemeKey) }
    }

    @Published var cheatsheetShortcut: SpecialShortcut {
        didSet { saveSpecialShortcut(cheatsheetShortcut, forKey: cheatsheetShortcutKey) }
    }

    @Published var appAssigningShortcut: SpecialShortcut {
        didSet { saveSpecialShortcut(appAssigningShortcut, forKey: appAssigningShortcutKey) }
    }


    @Published private(set) var systemColorScheme: ColorScheme = .light

    private var appearanceCancellable: AnyCancellable?

    var currentProfile: Binding<Profile> {
        Binding(
            get: {
                guard let index = self.profiles.firstIndex(where: { $0.id == self.currentProfileID }) else {
                    return self.profiles.first ?? Profile(name: "Default", assignments: [])
                }
                return self.profiles[index]
            },
            set: { updatedProfile in
                if let index = self.profiles.firstIndex(where: { $0.id == updatedProfile.id }) {
                    self.profiles[index] = updatedProfile
                }
            }
        )
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        self.showMenuBarIcon = UserDefaults.standard.object(forKey: menuBarIconKey) == nil ? true : UserDefaults.standard.bool(forKey: menuBarIconKey)

        if let rawValue = UserDefaults.standard.string(forKey: colorSchemeKey), let scheme = ColorSchemeSetting(rawValue: rawValue) {
            self.colorScheme = scheme
        } else {
            self.colorScheme = .auto
        }

        if let rawValue = UserDefaults.standard.string(forKey: appThemeKey), let theme = Theme(rawValue: rawValue) {
            self.appTheme = theme
        } else {
            self.appTheme = .greenish
        }

        self.cheatsheetShortcut = Self.loadAndMigrateSpecialShortcut(newKey: cheatsheetShortcutKey, oldKey: oldCheatsheetShortcutKey)
        self.appAssigningShortcut = Self.loadAndMigrateSpecialShortcut(newKey: appAssigningShortcutKey, oldKey: oldAppAssigningShortcutKey)

        var loadedProfiles = SettingsManager.loadAndMigrateProfiles(from: profilesKey)
        if loadedProfiles.isEmpty {
            loadedProfiles.append(SettingsManager.createDefaultProfile())
        }
        self.profiles = loadedProfiles
        
        if let uuidString = UserDefaults.standard.string(forKey: currentProfileIDKey), let uuid = UUID(uuidString: uuidString), loadedProfiles.contains(where: { $0.id == uuid }) {
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
    
    private static func loadAndMigrateSpecialShortcut(newKey: String, oldKey: String) -> SpecialShortcut {
        if let data = UserDefaults.standard.data(forKey: newKey),
           let decodedShortcut = try? JSONDecoder().decode(SpecialShortcut.self, from: data) {
            return decodedShortcut
        }
        
        if let data = UserDefaults.standard.data(forKey: oldKey),
           let oldKeys = try? JSONDecoder().decode([ShortcutKey].self, from: data) {
            let migratedShortcut = SpecialShortcut(keys: oldKeys, trigger: .press)
            if let encoded = try? JSONEncoder().encode(migratedShortcut) {
                UserDefaults.standard.set(encoded, forKey: newKey)
                UserDefaults.standard.removeObject(forKey: oldKey)
            }
            return migratedShortcut
        }
        
        return SpecialShortcut(keys: [], trigger: .press)
    }

    private static func loadAndMigrateProfiles(from key: String) -> [Profile] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
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
                            let modifiersToApply = oldProfile.triggerModifiers[category] ?? []
                            newShortcut.append(contentsOf: modifiersToApply.map { ShortcutKey.from(keyCode: $0.keyCode, isModifier: $0.isTrueModifier, isSystemEvent: false) })
                            if let kc = oldAssignment.keyCode { newShortcut.append(ShortcutKey.from(keyCode: kc, isModifier: false, isSystemEvent: false)) }
                            return Assignment(id: oldAssignment.id, shortcut: newShortcut, trigger: .press, configuration: oldAssignment.configuration)
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

        do {
            let profiles = try JSONDecoder().decode([Profile].self, from: data)
            if !profiles.isEmpty {
                return profiles
            }
        } catch {
            struct OldProfile: Decodable {
                let id: UUID
                let name: String
                let assignments: [OldAssignment]
            }

            struct OldAssignment: Decodable {
                let id: UUID
                let shortcut: [ShortcutKey]
                let trigger: ShortcutTriggerType
                let configuration: OldConfiguration
            }

            struct OldConfiguration: Decodable {
                let target: OldShortcutTarget
                let behavior: ShortcutConfiguration.Behavior
            }

            enum OldShortcutTarget: Decodable {
                case app(bundleId: String)
                case url(String)
                case file(String)
                case script(command: String, runsInTerminal: Bool)
                case shortcut(name: String)
            }

            if let oldProfiles = try? JSONDecoder().decode([OldProfile].self, from: data) {
                let migratedProfiles = oldProfiles.map { oldProfile -> Profile in
                    let newAssignments = oldProfile.assignments.map { oldAssignment -> Assignment in
                        let newTarget: ShortcutTarget
                        switch oldAssignment.configuration.target {
                            case .app(let id): newTarget = .app(bundleId: id)
                            case .url(let s): newTarget = .url(s)
                            case .file(let s): newTarget = .file(s)
                            case .shortcut(let n): newTarget = .shortcut(name: n)
                            case .script(let c, let r): newTarget = .script(name: "Script", command: c, runsInTerminal: r)
                        }
                        
                        let newConfig = ShortcutConfiguration(target: newTarget, behavior: oldAssignment.configuration.behavior)
                        return Assignment(id: oldAssignment.id, shortcut: oldAssignment.shortcut, trigger: oldAssignment.trigger, configuration: newConfig)
                    }
                    return Profile(id: oldProfile.id, name: oldProfile.name, assignments: newAssignments)
                }
                
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

    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }
    }

    private func saveSpecialShortcut(_ shortcut: SpecialShortcut, forKey key: String) {
        if let encoded = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func addAssignment(_ assignment: Assignment) {
        currentProfile.wrappedValue.assignments.append(assignment)
    }

    func updateAssignment(id: UUID, newShortcut: [ShortcutKey], newTrigger: ShortcutTriggerType? = nil) {
        if let index = currentProfile.wrappedValue.assignments.firstIndex(where: { $0.id == id }) {
            currentProfile.wrappedValue.assignments[index].shortcut = newShortcut
            if let trigger = newTrigger {
                currentProfile.wrappedValue.assignments[index].trigger = trigger
            }
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


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
    case snippet = "Snippets"
    case shortcut = "Shortcuts"
    case url = "URLs"
    case file = "Files & Folders"
    case script = "Scripts"

    var id: String { self.rawValue }

    var systemImage: String {
        switch self {
        case .app: "square.grid.2x2.fill"
        case .snippet: "doc.text.fill"
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
    @Published private(set) var didPerformMigration: Bool = false

    private let oldBundleIdentifier = "com.musamatini.WrapKey"

    private let profilesKey = "WarpKey_Profiles_v6"
    private let currentProfileIDKey = "WarpKey_CurrentProfileID_v2"
    private let menuBarIconKey = "showMenuBarIcon_v1"
    private let onboardingKey = "hasCompletedOnboarding_v1"
    private let colorSchemeKey = "WarpKey_ColorScheme_v1"
    private let appThemeKey = "WarpKey_AppTheme_v1"
    private let cheatsheetShortcutKey = "WarpKey_CheatsheetShortcut_v2"
    private let appAssigningShortcutKey = "WarpKey_AppAssigningShortcut_v2"
    private let oldCheatsheetShortcutKey = "WarpKey_CheatsheetShortcut_v1"
    private let oldAppAssigningShortcutKey = "WarpKey_AppAssigningShortcut_v1"
    private let screenRecordingSkippedKey = "WarpKey_ScreenRecordingSkipped_v1"

    @Published var profiles: [Profile] { didSet { saveProfiles() } }
    @Published var currentProfileID: UUID { didSet { UserDefaults.standard.set(currentProfileID.uuidString, forKey: currentProfileIDKey); objectWillChange.send() } }
    @Published var showMenuBarIcon: Bool { didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: menuBarIconKey) } }
    @Published var hasCompletedOnboarding: Bool { didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey) } }
    @Published var colorScheme: ColorSchemeSetting { didSet { UserDefaults.standard.set(colorScheme.rawValue, forKey: colorSchemeKey) } }
    @Published var appTheme: Theme { didSet { UserDefaults.standard.set(appTheme.rawValue, forKey: appThemeKey) } }
    @Published var cheatsheetShortcut: SpecialShortcut { didSet { saveSpecialShortcut(cheatsheetShortcut, forKey: cheatsheetShortcutKey) } }
    @Published var appAssigningShortcut: SpecialShortcut { didSet { saveSpecialShortcut(appAssigningShortcut, forKey: appAssigningShortcutKey) } }
    @Published var hasSkippedScreenRecordingPermission: Bool {
        didSet { UserDefaults.standard.set(hasSkippedScreenRecordingPermission, forKey: screenRecordingSkippedKey) }
    }
    
    @Published private(set) var systemColorScheme: ColorScheme = .light
    private var appearanceCancellable: AnyCancellable?

    var currentProfile: Binding<Profile> {
        Binding(
            get: {
                guard let index = self.profiles.firstIndex(where: { $0.id == self.currentProfileID }) else { return self.profiles.first ?? Profile(name: "Default", assignments: []) }
                return self.profiles[index]
            },
            set: { updatedProfile in
                if let index = self.profiles.firstIndex(where: { $0.id == updatedProfile.id }) { self.profiles[index] = updatedProfile }
            }
        )
    }

    init() {
            self.hasSkippedScreenRecordingPermission = UserDefaults.standard.bool(forKey: screenRecordingSkippedKey)
            
            var migrationWasPerformedThisLaunch = false
            let migrationCompletedKey = "WarpKey_MigrationFromOldBundleIDCompleted_v5"

            if !UserDefaults.standard.bool(forKey: migrationCompletedKey) {
                if let oldDefaults = UserDefaults(suiteName: oldBundleIdentifier) {
                    print("Old data found for bundle ID '\(oldBundleIdentifier)'. Migrating ALL settings...")
                    
                    let keyMap = [
                        "WrapKey_Profiles_v6": self.profilesKey,
                        "WrapKey_CurrentProfileID_v2": self.currentProfileIDKey,
                        "WrapKey_ColorScheme_v1": self.colorSchemeKey,
                        "WrapKey_AppTheme_v1": self.appThemeKey,
                        "WrapKey_CheatsheetShortcut_v2": self.cheatsheetShortcutKey,
                        "WrapKey_AppAssigningShortcut_v2": self.appAssigningShortcutKey,
                        "WrapKey_CheatsheetShortcut_v1": self.oldCheatsheetShortcutKey,
                        "WrapKey_AppAssigningShortcut_v1": self.oldAppAssigningShortcutKey,
                        "showMenuBarIcon_v1": self.menuBarIconKey,
                        "hasCompletedOnboarding_v1": self.onboardingKey
                    ]
                    
                    var didMigrateSomething = false
                    for (oldKey, newKey) in keyMap {
                        if let value = oldDefaults.object(forKey: oldKey) {
                            UserDefaults.standard.set(value, forKey: newKey)
                            print("✅ Migrated: \(oldKey) -> \(newKey)")
                            didMigrateSomething = true
                        }
                    }
                    
                    let sparkleUpdateCheckKey = "SUEnableAutomaticChecks"
                    if let oldValue = oldDefaults.object(forKey: sparkleUpdateCheckKey) {
                        UserDefaults.standard.set(oldValue, forKey: sparkleUpdateCheckKey)
                        print("✅ Migrated Sparkle setting: SUEnableAutomaticChecks")
                        didMigrateSomething = true
                    }

                    if didMigrateSomething {
                        UserDefaults.standard.synchronize()
                        print("Migration successful.")
                        migrationWasPerformedThisLaunch = true
                    }
                } else {
                    print("No old data found. Skipping migration.")
                }
                UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            }

            self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
            self.showMenuBarIcon = UserDefaults.standard.object(forKey: menuBarIconKey) == nil ? true : UserDefaults.standard.bool(forKey: menuBarIconKey)
            if let rawValue = UserDefaults.standard.string(forKey: colorSchemeKey), let scheme = ColorSchemeSetting(rawValue: rawValue) { self.colorScheme = scheme } else { self.colorScheme = .auto }
            if let rawValue = UserDefaults.standard.string(forKey: appThemeKey), let theme = Theme(rawValue: rawValue) { self.appTheme = theme } else { self.appTheme = .greenish }
            self.cheatsheetShortcut = Self.loadAndMigrateSpecialShortcut(newKey: cheatsheetShortcutKey, oldKey: oldCheatsheetShortcutKey)
            self.appAssigningShortcut = Self.loadAndMigrateSpecialShortcut(newKey: appAssigningShortcutKey, oldKey: oldAppAssigningShortcutKey)
            var loadedProfiles = SettingsManager.loadAndMigrateProfiles(from: profilesKey)
            if loadedProfiles.isEmpty { loadedProfiles.append(SettingsManager.createDefaultProfile()) }
            self.profiles = loadedProfiles
            if let uuidString = UserDefaults.standard.string(forKey: currentProfileIDKey), let uuid = UUID(uuidString: uuidString), loadedProfiles.contains(where: { $0.id == uuid }) { self.currentProfileID = uuid } else { self.currentProfileID = loadedProfiles.first!.id }
            self.didPerformMigration = migrationWasPerformedThisLaunch
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
            return [createDefaultProfile()]
        }
        do {
            let profiles = try JSONDecoder().decode([Profile].self, from: data)
            return profiles.isEmpty ? [createDefaultProfile()] : profiles
        } catch {
            do {
                let intermediateProfiles = try JSONDecoder().decode([IntermediateProfile].self, from: data)
                let migratedProfiles = intermediateProfiles.map { $0.asNewProfile() }
                if let encoded = try? JSONEncoder().encode(migratedProfiles) {
                    UserDefaults.standard.set(encoded, forKey: key)
                }
                return migratedProfiles.isEmpty ? [createDefaultProfile()] : migratedProfiles
            } catch {
                do {
                    let oldProfiles = try JSONDecoder().decode([OldProfile].self, from: data)
                    let migratedProfiles = oldProfiles.map { $0.asNewProfile() }
                    if let encoded = try? JSONEncoder().encode(migratedProfiles) {
                        UserDefaults.standard.set(encoded, forKey: key)
                    }
                    return migratedProfiles.isEmpty ? [createDefaultProfile()] : migratedProfiles
                } catch {
                    return [createDefaultProfile()]
                }
            }
        }
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

private func appNameProvider(for bundleId: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return bundleId }
    if let bundle = Bundle(url: url),
       let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
       !name.isEmpty {
        return name
    }
    return FileManager.default.displayName(atPath: url.path)
}

private struct IntermediateProfile: Decodable {
    let id: UUID
    let name: String
    let assignments: [IntermediateAssignment]
    func asNewProfile() -> Profile {
        Profile(id: id, name: name, assignments: assignments.map { $0.asNewAssignment() })
    }
}
private struct IntermediateAssignment: Decodable {
    let id: UUID
    let shortcut: [ShortcutKey]
    let trigger: ShortcutTriggerType?
    let configuration: IntermediateConfiguration
    func asNewAssignment() -> Assignment {
        Assignment(id: id, shortcut: shortcut, trigger: trigger ?? .press, configuration: configuration.asNewConfiguration())
    }
}
private struct IntermediateConfiguration: Decodable {
    let target: IntermediateShortcutTarget
    let behavior: ShortcutConfiguration.Behavior
    func asNewConfiguration() -> ShortcutConfiguration {
        ShortcutConfiguration(target: target.asNewTarget(), behavior: behavior)
    }
}
private enum IntermediateShortcutTarget: Decodable {
    case app(name: String, bundleId: String)
    case url(name: String, address: String)
    case file(name: String, path: String)
    case script(name: String, command: String, runsInTerminal: Bool)
    case shortcut(name: String, executionName: String)
    enum CodingKeys: String, CodingKey { case app, url, file, script, shortcut }
    private enum AppKeys: String, CodingKey { case name, bundleId }
    private enum URLKeys: String, CodingKey { case name, address }
    private enum FileKeys: String, CodingKey { case name, path }
    private enum ScriptKeys: String, CodingKey { case name, command, runsInTerminal }
    private enum ShortcutKeys: String, CodingKey { case name, executionName }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let payload = try? c.nestedContainer(keyedBy: AppKeys.self, forKey: .app) { self = .app(name: try payload.decode(String.self, forKey: .name), bundleId: try payload.decode(String.self, forKey: .bundleId)) }
        else if let payload = try? c.nestedContainer(keyedBy: URLKeys.self, forKey: .url) { self = .url(name: try payload.decode(String.self, forKey: .name), address: try payload.decode(String.self, forKey: .address)) }
        else if let payload = try? c.nestedContainer(keyedBy: FileKeys.self, forKey: .file) { self = .file(name: try payload.decode(String.self, forKey: .name), path: try payload.decode(String.self, forKey: .path)) }
        else if let payload = try? c.nestedContainer(keyedBy: ScriptKeys.self, forKey: .script) { self = .script(name: try payload.decode(String.self, forKey: .name), command: try payload.decode(String.self, forKey: .command), runsInTerminal: try payload.decode(Bool.self, forKey: .runsInTerminal)) }
        else if let payload = try? c.nestedContainer(keyedBy: ShortcutKeys.self, forKey: .shortcut) { self = .shortcut(name: try payload.decode(String.self, forKey: .name), executionName: try payload.decode(String.self, forKey: .executionName)) }
        else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: c.codingPath, debugDescription: "Corrupt data")) }
    }
    func asNewTarget() -> ShortcutTarget {
        switch self {
        case .app(let n, let b): return .app(name: n, bundleId: b)
        case .url(let n, let a): return .url(name: n, address: a)
        case .file(let n, let p): return .file(name: n, path: p)
        case .script(let n, let c, let r): return .script(name: n, command: c, runsInTerminal: r)
        case .shortcut(let n, let e): return .shortcut(name: n, executionName: e)
        }
    }
}

private struct OldProfile: Decodable {
    let id: UUID
    let name: String
    let assignments: [OldAssignment]
    func asNewProfile() -> Profile {
        Profile(id: id, name: name, assignments: assignments.map { $0.asNewAssignment() })
    }
}
private struct OldAssignment: Decodable {
    let id: UUID
    let shortcut: [ShortcutKey]
    let trigger: ShortcutTriggerType?
    let configuration: OldConfiguration
    func asNewAssignment() -> Assignment {
        Assignment(id: id, shortcut: shortcut, trigger: trigger ?? .press, configuration: configuration.asNewConfiguration())
    }
}
private struct OldConfiguration: Decodable {
    let target: OldShortcutTarget
    let behavior: ShortcutConfiguration.Behavior
    func asNewConfiguration() -> ShortcutConfiguration {
        ShortcutConfiguration(target: target.asNewTarget(), behavior: behavior)
    }
}
private enum OldShortcutTarget: Decodable {
    case app(bundleId: String)
    case url(String)
    case file(String)
    case script(name: String, command: String, runsInTerminal: Bool)
    case shortcut(name: String)
    enum CodingKeys: String, CodingKey { case app, url, file, script, shortcut }
    private enum AppKeys: String, CodingKey { case bundleId }
    private enum ShortcutKeys: String, CodingKey { case name }
    private enum ScriptKeys: String, CodingKey { case name, command, runsInTerminal }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.app) {
            do { self = .app(bundleId: try c.nestedContainer(keyedBy: AppKeys.self, forKey: .app).decode(String.self, forKey: .bundleId)) }
            catch { self = .app(bundleId: try c.decode(String.self, forKey: .app)) }
        } else if c.contains(.url) { self = .url(try c.decode(String.self, forKey: .url)) }
        else if c.contains(.file) { self = .file(try c.decode(String.self, forKey: .file)) }
        else if c.contains(.shortcut) {
            do { self = .shortcut(name: try c.nestedContainer(keyedBy: ShortcutKeys.self, forKey: .shortcut).decode(String.self, forKey: .name)) }
            catch { self = .shortcut(name: try c.decode(String.self, forKey: .shortcut)) }
        } else if c.contains(.script) { let s = try c.nestedContainer(keyedBy: ScriptKeys.self, forKey: .script); self = .script(name: try s.decodeIfPresent(String.self, forKey: .name) ?? "Script", command: try s.decode(String.self, forKey: .command), runsInTerminal: try s.decode(Bool.self, forKey: .runsInTerminal)) }
        else { throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Corrupt data")) }
    }
    func asNewTarget() -> ShortcutTarget {
        switch self {
        case .app(let b): return .app(name: appNameProvider(for: b), bundleId: b)
        case .url(let u): return .url(name: URL(string: u)?.host ?? "Link", address: u)
        case .file(let p): return .file(name: URL(fileURLWithPath: p).lastPathComponent, path: p)
        case .script(let n, let c, let r): return .script(name: n, command: c, runsInTerminal: r)
        case .shortcut(let n): return .shortcut(name: n, executionName: n)
        }
    }
}

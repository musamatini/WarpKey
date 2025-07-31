//Views.swift
import SwiftUI
import AppKit
import Sparkle

// MARK: - Navigation Enums
enum SheetType: Identifiable, Equatable {
    case addURL, addFile, addScript, addShortcut, addApp
    case editURL(assignment: Assignment)
    case editScript(assignment: Assignment)
    case editFile(assignment: Assignment)

    var id: String {
        switch self {
        case .addURL: "addURL"
        case .addFile: "addFile"
        case .addScript: "addScript"
        case .addShortcut: "addShortcut"
        case .addApp: "addApp"
        case .editURL(let assignment): "editURL-\(assignment.id)"
        case .editScript(let assignment): "editScript-\(assignment.id)"
        case .editFile(let assignment): "editFile-\(assignment.id)"
        }
    }
    
    static func == (lhs: SheetType, rhs: SheetType) -> Bool {
        lhs.id == rhs.id
    }
}

enum AppPage: Hashable {
    case welcome, settings, help, appSettings
}

// MARK: - Custom View Modifiers
struct PillButton: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .fontWeight(.semibold)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(AppTheme.pillBackgroundColor(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
    }
}

// MARK: - Root Views
struct MenuView: View {
    @ObservedObject var manager: AppHotKeyManager
    @ObservedObject var launchManager: LaunchAtLoginManager
    @ObservedObject var updaterViewModel: UpdaterViewModel
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var currentPage: AppPage = .settings
    
    var body: some View {
        ZStack {
            if !manager.hasAccessibilityPermissions {
                PermissionsRestartRequiredView()
            } else if !settings.hasCompletedOnboarding {
                WelcomePage(
                    manager: manager,
                    onGetStarted: {
                        settings.hasCompletedOnboarding = true
                    },
                    onGoToHelp: {
                        settings.hasCompletedOnboarding = true
                        currentPage = .help
                    }
                )
            } else {
                MainTabView(
                    manager: manager,
                    launchManager: launchManager,
                    updaterViewModel: updaterViewModel,
                    initialTab: currentPage
                )
            }
        }
        .frame(width: 450, height: 700)
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .animation(.default, value: manager.hasAccessibilityPermissions)
        .animation(.default, value: settings.hasCompletedOnboarding)
    }
}


struct MainTabView: View {
    @ObservedObject var manager: AppHotKeyManager
    @ObservedObject var launchManager: LaunchAtLoginManager
    @ObservedObject var updaterViewModel: UpdaterViewModel
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedTab: AppPage

    init(manager: AppHotKeyManager, launchManager: LaunchAtLoginManager, updaterViewModel: UpdaterViewModel, initialTab: AppPage) {
        self.manager = manager
        self.launchManager = launchManager
        self.updaterViewModel = updaterViewModel
        self._selectedTab = State(initialValue: initialTab)
    }
    
    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme).ignoresSafeArea()
            
            switch selectedTab {
            case .settings:
                MainSettingsView(manager: manager, showHelpPage: { selectedTab = .help }, showAppSettingsPage: { selectedTab = .appSettings })
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .identity))
            case .help:
                HelpView(manager: manager, goBack: { selectedTab = .settings })
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            case .appSettings:
                AppSettingsView(
                    manager: manager,
                    launchManager: launchManager,
                    updaterViewModel: updaterViewModel,
                    goBack: { selectedTab = .settings }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            case .welcome:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
        .onReceive(NotificationCenter.default.publisher(for: .goToHelpPageInMainWindow)) { _ in
            selectedTab = .help
        }
    }
}

// MARK: - Main Settings Screen
struct MainSettingsView: View {
    @ObservedObject var manager: AppHotKeyManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var showHelpPage: () -> Void
    var showAppSettingsPage: () -> Void

    @State private var showingSheet: SheetType?
    
    private var categorizedAssignments: [ShortcutCategory: [Assignment]] {
        Dictionary(grouping: settings.currentProfile.wrappedValue.assignments.sorted(by: {
            let key0 = $0.keyCode.map { manager.keyString(for: $0) } ?? " "
            let key1 = $1.keyCode.map { manager.keyString(for: $0) } ?? " "
            return key0 < key1
        })) { $0.configuration.target.category }
    }
    private let categoryOrder: [ShortcutCategory] = [.app, .shortcut, .url, .file, .script]

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme).ignoresSafeArea()
            VStack(spacing: 0) {
                CustomTitleBar(title: "WrapKey", onClose: { dismiss() })
                    .environmentObject(settings)
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 18, pinnedViews: .sectionHeaders) {
                        if settings.currentProfile.wrappedValue.assignments.isEmpty {
                            EmptyStateView(manager: manager)
                        } else {
                            ForEach(categoryOrder, id: \.self) { category in
                                if let items = categorizedAssignments[category], !items.isEmpty {
                                    Section(header: CategoryHeader(category: category)) {
                                        ForEach(items) { assignment in
                                            AssignmentRow(manager: manager, assignment: assignment)
                                        }
                                    }
                                }
                            }
                        }
                        Spacer().frame(height: 133)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .safeAreaInset(edge: .bottom) {
                FooterView(onShowHelp: showHelpPage, onShowAppSettings: showAppSettingsPage, sheetType: $showingSheet)
            }
            if manager.isListeningForAssignment {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { manager.isListeningForAssignment = false }
                    VStack(spacing: 20) {
                        ProgressView().progressViewStyle(.circular).tint(AppTheme.accentColor1(for: colorScheme))
                        Text("Press a key to assign...").font(.title3).foregroundColor(AppTheme.primaryTextColor(for: .dark))
                        Text("Only letter and number keys can be assigned.").font(.callout).foregroundColor(AppTheme.secondaryTextColor(for: .dark)).multilineTextAlignment(.center)
                        
                        Button("Set Without Hotkey") {
                            manager.completeAssignmentWithoutKey()
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.secondaryTextColor(for: .dark))
                        .controlSize(.large)
                        .padding(.top, 10)
                        
                    }.padding(30).background(VisualEffectBlur().clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))).shadow(radius: 20)
                }.transition(.opacity)
            }
        }
        .sheet(item: $showingSheet) { item in
            switch item {
            case .addApp:
                AppPickerView { bundleId in
                    manager.listenForNewAssignment(target: .app(bundleId: bundleId))
                }
            case .addURL:
                AddURLView { url in manager.listenForNewAssignment(target: .url(url)) }
            case .addFile:
                AddFileView { path in manager.listenForNewAssignment(target: .file(path)) }
            case .addScript:
                AddScriptView { command, runsInTerminal in manager.listenForNewAssignment(target: .script(command: command, runsInTerminal: runsInTerminal)) }
            case .addShortcut:
                ShortcutPickerView { name in manager.listenForNewAssignment(target: .shortcut(name: name)) }
            case .editURL, .editScript, .editFile:
                EmptyView()
            }
        }
    }
}


// MARK: - App Settings Screen
struct AppSettingsView: View {
    @ObservedObject var manager: AppHotKeyManager
    @ObservedObject var launchManager: LaunchAtLoginManager
    @ObservedObject var updaterViewModel: UpdaterViewModel
    
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var goBack: () -> Void
    
    @State private var isShowingConfirmationAlert = false
    @State private var isShowingProfileNameAlert = false
    @State private var isShowingDeleteProfileAlert = false
    @State private var isEditingExistingProfile = false
    @State private var potentialNewKey: ModifierKey? = nil
    @State private var profileToDelete: Profile?
    @State private var profileNameField = ""
    private let authorURL = URL(string: "https://musa.matini.link")!

  

    @Namespace private var themePickerNamespace
    private let keyPressPublisher = NotificationCenter.default.publisher(for: .keyPressEvent)
    
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "N/A"
        return "\(version) (build \(build))"
    }

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme).ignoresSafeArea()
            VStack(spacing: 0) {
                CustomTitleBar(title: "WrapKey Settings", showBackButton: true, onBack: goBack, onClose: { dismiss() })
                    .environmentObject(settings)
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        HelpSection(title: "General") {
                            Toggle("Show Menu Bar Icon", isOn: $settings.showMenuBarIcon)
                                .toggleStyle(CustomSwitchToggleStyle())
                            
                            Toggle("Launch at Login", isOn: $launchManager.isEnabled)
                                .toggleStyle(CustomSwitchToggleStyle())
                        }

                        HelpSection(title: "Appearance") {
                            CustomSegmentedPicker(
                                title: "Appearance",
                                selection: $settings.colorScheme,
                                in: themePickerNamespace
                            )
                        }

                        HelpSection(title: "Profiles") {
                            VStack(spacing: 8) {
                                ForEach(settings.profiles) { profile in
                                    ProfileRowView(profile: profile, isSelected: profile.id == settings.currentProfileID)
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                settings.currentProfileID = profile.id
                                            }
                                        }
                                }
                            }
                            Divider().padding(.vertical, 4)
                            HStack(spacing: 10) {
                                Button("Add New") {
                                    profileNameField = ""
                                    isEditingExistingProfile = false
                                    isShowingProfileNameAlert = true
                                }.modifier(PillButton())
                                
                                Button("Rename") {
                                    profileNameField = settings.currentProfile.wrappedValue.name
                                    isEditingExistingProfile = true
                                    isShowingProfileNameAlert = true
                                }.modifier(PillButton())
                                
                                Button("Delete") {
                                    profileToDelete = settings.currentProfile.wrappedValue
                                    isShowingDeleteProfileAlert = true
                                }
                                .modifier(PillButton())
                                .foregroundColor(.red.opacity(0.9))
                                .disabled(settings.profiles.count <= 1)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        HelpSection(title: "Trigger Keys for \"\(settings.currentProfile.wrappedValue.name)\"") {
                            VStack(spacing: 16) {
                                ForEach(ShortcutCategory.allCases, id: \.self) { category in
                                    ModifierKeySelector(
                                        title: category.rawValue,
                                        isListening: manager.isListeningForNewModifier && manager.modifierToChange?.category == category,
                                        keys: settings.currentProfile.wrappedValue.triggerModifiers[category] ?? [],
                                        onAdd: {
                                            manager.modifierToChange = (category, .trigger)
                                            manager.isListeningForNewModifier = true
                                        },
                                        onRemove: { key in
                                            settings.removeModifierKey(key, for: category, type: .trigger)
                                        }
                                    )
                                }
                            }
                        }
                        
                        HelpSection(title: "Secondary Keys (for App Assignment)") {
                            ModifierKeySelector(
                                title: "",
                                isListening: manager.isListeningForNewModifier && manager.modifierToChange?.type == .secondary,
                                keys: settings.currentProfile.wrappedValue.secondaryModifier,
                                onAdd: {
                                    manager.modifierToChange = (.app, .secondary)
                                    manager.isListeningForNewModifier = true
                                },
                                onRemove: { key in
                                    settings.removeModifierKey(key, for: .app, type: .secondary)
                                }
                            )
                        }
                        
                        HelpSection(title: "Data Management") {
                            HStack(spacing: 10) {
                                Button("Import All Profiles...") { importSettings() }.modifier(PillButton())
                                Button("Export All Profiles...") { exportSettings() }.modifier(PillButton())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        HelpSection(title: "Updates") {
                            Toggle("Check for updates automatically", isOn: $updaterViewModel.automaticallyChecksForUpdates)
                                .toggleStyle(CustomSwitchToggleStyle())
                            
                            Divider()
                                .padding(.vertical, 4)

                            Button("Check for Updates Now") {
                                updaterViewModel.checkForUpdates()
                            }
                            .modifier(PillButton())
                            .buttonStyle(.plain)
                            .disabled(!updaterViewModel.canCheckForUpdates)
                        }
                        
                        VStack(spacing: 4) {
                            HStack(spacing: 0) {
                                Text("Made with ")
                                Text(Image(systemName: "heart.fill"))
                                    .foregroundColor(AppTheme.accentColor1(for: colorScheme))
                                Text(" by ")
                                Link("Musa Matini", destination: authorURL)
                                    .buttonStyle(.plain)
                                    .foregroundColor(AppTheme.accentColor1(for: colorScheme))
                            }
                            
                            Text("WrapKey Version \(appVersion)")
                        }
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 3)

                    }
                    .padding()
                }
            }
            if manager.isListeningForNewModifier {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { manager.isListeningForNewModifier = false }
                    VStack(spacing: 20) {
                        ProgressView().progressViewStyle(.circular).tint(AppTheme.accentColor1(for: colorScheme))
                        Text("Press any key...").font(.title3).foregroundColor(AppTheme.primaryTextColor(for: .dark))
                        Text("You will be asked to confirm if you select a non-modifier key.")
                            .font(.callout).foregroundColor(AppTheme.secondaryTextColor(for: .dark)).multilineTextAlignment(.center)
                    }.padding(30).background(VisualEffectBlur().clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))).shadow(radius: 20)
                }.transition(.opacity)
            }
        }
        .onReceive(keyPressPublisher) { notification in handleKeyPress(notification: notification) }
        .alert("Set Key", isPresented: $isShowingConfirmationAlert, presenting: potentialNewKey) { key in
            Button("Confirm", role: .destructive) { if let changeInfo = manager.modifierToChange { settings.addModifierKey(key, for: changeInfo.category, type: changeInfo.type) } }
            Button("Cancel", role: .cancel) {}
        } message: { key in Text("Set '\(key.displayName)' as a \(manager.modifierToChange?.type == .trigger ? "Trigger" : "Secondary") key? You will no longer be able to type this key normally.") }
        .alert(isEditingExistingProfile ? "Rename Profile" : "New Profile", isPresented: $isShowingProfileNameAlert) {
            TextField("Profile Name", text: $profileNameField)
            Button("Save") {
                if isEditingExistingProfile { settings.currentProfile.wrappedValue.name = profileNameField }
                else { settings.addNewProfile(name: profileNameField.isEmpty ? "New Profile" : profileNameField) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Profile", isPresented: $isShowingDeleteProfileAlert, presenting: profileToDelete) { profile in
            Button("Delete \"\(profile.name)\"", role: .destructive) { settings.deleteProfile(id: profile.id) }
        }
    }
    
    private func handleKeyPress(notification: Notification) {
        guard manager.isListeningForNewModifier,
              let changeInfo = manager.modifierToChange else { return }

        let event = notification.object as! CGEvent
        manager.isListeningForNewModifier = false
        
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let newKey = ModifierKey.from(keyCode: keyCode)
        
        let currentKeysForThisSelector: [ModifierKey]
        if changeInfo.type == .trigger {
            currentKeysForThisSelector = settings.currentProfile.wrappedValue.triggerModifiers[changeInfo.category] ?? []
        } else {
            currentKeysForThisSelector = settings.currentProfile.wrappedValue.secondaryModifier
        }
        
        if currentKeysForThisSelector.contains(where: { $0.keyCode == newKey.keyCode }) {
            NotificationManager.shared.sendNotification(title: "Key Already Used", body: "'\(newKey.displayName)' is already in this list.")
            return
        }
        
        if changeInfo.type == .trigger {
            let potentialNewTriggerSet = Set((settings.currentProfile.wrappedValue.triggerModifiers[changeInfo.category] ?? []) + [newKey])
            let secondaryKeySet = Set(settings.currentProfile.wrappedValue.secondaryModifier)
            
            if !secondaryKeySet.isEmpty && potentialNewTriggerSet == secondaryKeySet {
                NotificationManager.shared.sendNotification(title: "Identical Combination", body: "Trigger keys and Secondary keys cannot be identical.")
                return
            }
        } else { // type is .secondary
            let potentialNewSecondarySet = Set(settings.currentProfile.wrappedValue.secondaryModifier + [newKey])
            for (category, triggerKeys) in settings.currentProfile.wrappedValue.triggerModifiers {
                let triggerKeySet = Set(triggerKeys)
                if !triggerKeySet.isEmpty && potentialNewSecondarySet == triggerKeySet {
                    NotificationManager.shared.sendNotification(title: "Identical Combination", body: "This combination is already used as the trigger for '\(category.rawValue)'.")
                    return
                }
            }
        }

        if newKey.isTrueModifier {
            settings.addModifierKey(newKey, for: changeInfo.category, type: changeInfo.type)
        } else {
            potentialNewKey = newKey
            isShowingConfirmationAlert = true
        }
    }
    
    private func exportSettings() {
        let savePanel = NSSavePanel(); savePanel.allowedContentTypes = [.json]; savePanel.nameFieldStringValue = "WrapKey_Settings.json"
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(settings.profiles)
                try data.write(to: url)
                NotificationManager.shared.sendNotification(title: "Export Successful", body: "Your settings have been saved.")
            } catch { print("Failed to export settings: \(error)") }
        }
    }

    private func importSettings() {
        let openPanel = NSOpenPanel(); openPanel.allowedContentTypes = [.json]; openPanel.canChooseFiles = true; openPanel.canChooseDirectories = false
        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()

                let importedProfiles: [Profile]
                do {
                    importedProfiles = try decoder.decode([Profile].self, from: data)
                } catch {
                    struct OldProfileV4: Codable {
                        var id: UUID, name: String, triggerModifiers: [ShortcutCategory: ModifierKey], secondaryModifier: ModifierKey, assignments: [Assignment]
                    }
                    let oldProfiles = try decoder.decode([OldProfileV4].self, from: data)
                    importedProfiles = oldProfiles.map { old -> Profile in
                        var newTriggers = old.triggerModifiers.mapValues { [$0] }
                        for category in ShortcutCategory.allCases where newTriggers[category] == nil {
                            newTriggers[category] = newTriggers[.app] ?? [ModifierKey.from(keyCode: 54)]
                        }
                        return Profile(id: old.id, name: old.name, triggerModifiers: newTriggers, secondaryModifier: [old.secondaryModifier], assignments: old.assignments)
                    }
                }

                var validShortcutsCount = 0; var skippedShortcutsCount = 0
                let validatedProfiles = importedProfiles.map { profile -> Profile in
                    var newProfile = profile; var validatedAssignments: [Assignment] = []
                    for assignment in profile.assignments {
                        if case .app(let bundleId) = assignment.configuration.target {
                            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
                                validatedAssignments.append(assignment); validShortcutsCount += 1
                            } else { skippedShortcutsCount += 1 }
                        } else { validatedAssignments.append(assignment); validShortcutsCount += 1 }
                    }
                    newProfile.assignments = validatedAssignments; return newProfile
                }
                settings.profiles = validatedProfiles; settings.currentProfileID = validatedProfiles.first?.id ?? UUID()
                NotificationManager.shared.sendNotification(title: "Import Complete", body: "\(validShortcutsCount) shortcuts imported. \(skippedShortcutsCount) for missing apps were skipped.")
            } catch { NotificationManager.shared.sendNotification(title: "Import Failed", body: "The selected file is not a valid WrapKey settings file.") }
        }
    }
}

// MARK: - Permissions Screen
struct PermissionsRestartRequiredView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 35) {
                VStack(spacing: 15) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 50, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(AppTheme.accentColor1(for: colorScheme))
                    Text("Accessibility Access Required")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
                
                VStack(alignment: .center, spacing: 15) {
                    Text("WrapKey needs your permission to listen for keyboard events.")
                        .fontWeight(.semibold)
                    
                    Text("1. Click **Open System Settings**.\n2. Find **WrapKey** in the list and turn it on.\n3. Return here and click **Relaunch App**.")
                }
                .font(.callout)
                .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                .multilineTextAlignment(.leading)
                .lineSpacing(5)
                .padding()
                .background(AppTheme.pillBackgroundColor(for: colorScheme))
                .cornerRadius(AppTheme.cornerRadius)
                .padding(.horizontal, 40)
            }
            Spacer()
            
            VStack(spacing: 16) {
                Button(action: { AccessibilityManager.requestPermissions() }) {
                    Text("Open System Settings")
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                        .background(AppTheme.accentColor1(for: colorScheme))
                        .cornerRadius(50)
                }
                .buttonStyle(.plain)
                
                Button(action: { NotificationCenter.default.post(name: .requestAppRestart, object: nil) }) {
                    Text("Relaunch App")
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                        .background(AppTheme.pillBackgroundColor(for: colorScheme))
                        .cornerRadius(50)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 50)
            .padding(.bottom, 50)
        }
        .frame(width: 450, height: 700)
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
    }
}


// MARK: - Welcome Screen
struct WelcomePage: View {
    @ObservedObject var manager: AppHotKeyManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    var onGetStarted: () -> Void
    var onGoToHelp: () -> Void
    
    @State private var isShowingContent = false
    private let donationURL = URL(string: "https://www.patreon.com/MusaMatini")!
    private let githubURL = URL(string: "https://github.com/musamatini/WrapKey")!
    
    private var appTriggerString: String {
        manager.modifierKeyCombinationString(for: settings.currentProfile.wrappedValue.triggerModifiers[.app] ?? [])
    }
    
    private var secondaryTriggerString: String {
        manager.modifierKeyCombinationString(for: settings.currentProfile.wrappedValue.secondaryModifier)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            VStack(spacing: 35) {
                VStack(spacing: 15) {
                    Image(systemName: "sparkles").font(.system(size: 50, weight: .bold)).symbolRenderingMode(.monochrome).foregroundStyle(AppTheme.accentColor1(for: colorScheme))
                    Text("Welcome to WrapKey").font(.system(size: 32, weight: .bold, design: .rounded))
                }.opacity(isShowingContent ? 1 : 0).animation(.easeInOut(duration: 0.7), value: isShowingContent)
                
                VStack(alignment: .leading, spacing: 25) {
                    WelcomeActionRow(icon: "plus.app.fill", title: "Assign an App", subtitle: "Use **\(secondaryTriggerString) + \(appTriggerString) + [Letter]** when an app is frontmost.")
                    WelcomeActionRow(icon: "bolt.horizontal.circle.fill", title: "Use a Shortcut", subtitle: "Press **[Trigger Keys] + [Letter]** to launch, hide, or run your shortcut.")
                }.padding(.horizontal, 40).opacity(isShowingContent ? 1 : 0).animation(.easeInOut(duration: 0.7).delay(0.1), value: isShowingContent)
                
                (Text("Check the ") + Text("How to Use").bold().foregroundColor(AppTheme.accentColor1(for: colorScheme)).underline() + Text(" page for more info."))
                    .font(.callout).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)).multilineTextAlignment(.center).lineSpacing(5)
                    .onTapGesture { onGoToHelp() }
                    .opacity(isShowingContent ? 1 : 0).animation(.easeInOut(duration: 0.7).delay(0.2), value: isShowingContent)
                
                VStack(spacing: 18) {
                    Link(destination: githubURL) { HStack(spacing: 8) { Image(systemName: "ant.circle.fill"); Text("Report a bug or suggest a feature") } }
                    Link(destination: donationURL) { HStack(spacing: 8) { Image(systemName: "heart.circle.fill"); Text("Support me and the project") } }
                }.font(.callout).buttonStyle(.plain).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme).opacity(0.8))
                 .opacity(isShowingContent ? 1 : 0).animation(.easeInOut(duration: 0.7).delay(0.3), value: isShowingContent)
            }
            Spacer()
            Button(action: onGetStarted) {
                Text("Continue to App").font(.headline.weight(.semibold)).padding(.horizontal, 40).padding(.vertical, 14).foregroundColor(AppTheme.primaryTextColor(for: colorScheme)).background(AppTheme.accentColor1(for: colorScheme)).cornerRadius(50)
            }.buttonStyle(.plain).opacity(isShowingContent ? 1 : 0).animation(.easeInOut(duration: 0.7).delay(0.4), value: isShowingContent).padding(.bottom, 50)
        }
        .frame(width: 450, height: 700).foregroundColor(AppTheme.primaryTextColor(for: colorScheme)).background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.isShowingContent = true } }
    }
}

// MARK: - Help Screen
struct HelpView: View {
    @ObservedObject var manager: AppHotKeyManager
    var goBack: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    
    private var appTriggerString: String {
        manager.modifierKeyCombinationString(for: settings.currentProfile.wrappedValue.triggerModifiers[.app] ?? [])
    }
    
    private var secondaryTriggerString: String {
        manager.modifierKeyCombinationString(for: settings.currentProfile.wrappedValue.secondaryModifier)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            CustomTitleBar(title: "How to Use", showBackButton: true, onBack: goBack, onClose: { dismiss() })
                .environmentObject(settings)
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    
                    HelpSection(title: "Core Actions") {
                        HelpDetailRow(icon: "plus.app.fill", title: "Assign an App", subtitle: "Bring an app to the front, then press **\(secondaryTriggerString) + \(appTriggerString) + [Letter]**.")
                        HelpDetailRow(icon: "bolt.horizontal.circle.fill", title: "Use a Shortcut", subtitle: "Anywhere in macOS, press **[Trigger Keys] + [Letter]** to trigger your shortcut.")
                        HelpDetailRow(icon: "plus", title: "Add Other Shortcuts", subtitle: "Use the **+ Add Shortcut** button to create shortcuts for URLs, files, folders, and shell scripts.")
                        HelpDetailRow(icon: "pencil.and.scribble", title: "Edit a Shortcut", subtitle: "For URLs, Scripts, and Files, click the pencil icon to either change the hotkey or update its content (the URL, command, or file path).")
                    }
                    
                    HelpSection(title: "Shortcut Types") {
                        HelpDetailRow(icon: "app.dashed", title: "Apps", subtitle: "The standard behavior. Launches, hides, or cycles windows of an application.")
                        HelpDetailRow(icon: "square.stack.3d.up.fill", title: "macOS Shortcuts", subtitle: "Runs a shortcut from Apple's Shortcuts app by its exact name.")
                        HelpDetailRow(icon: "globe", title: "URLs", subtitle: "Opens the web address in your default browser.")
                        HelpDetailRow(icon: "doc", title: "Files & Folders", subtitle: "Opens the selected file with its default app, or opens the folder in Finder.")
                        HelpDetailRow(icon: "terminal", title: "Scripts", subtitle: "Executes the shell command. Can be run silently in the background or in a new Terminal window.")
                    }
                    
                    HelpSection(title: "Advanced Features") {
                        HelpDetailRow(icon: "keyboard.onehanded.left.fill", title: "Hyper Keys", subtitle: "Assign multiple keys (like ⌘ + ⌥ + ⌃) to a single trigger group. This creates a unique 'Hyper Key' that won't conflict with other app shortcuts.")
                        HelpDetailRow(icon: "person.2.fill", title: "Profiles", subtitle: "Create different sets of shortcuts and trigger keys for different contexts (e.g., 'Work', 'Studying'). Manage them in App Settings.")
                        HelpDetailRow(icon: "keyboard.fill", title: "Per-Type Triggers", subtitle: "Assign a different Trigger Key combination for each category of shortcut (Apps, URLs, etc.) for ultimate control.")
                        HelpDetailRow(icon: "exclamationmark.triangle.fill", title: "Hotkey Conflicts", subtitle: "If a hotkey is assigned to multiple actions, a warning will appear. When pressed, all conflicting actions will run.")
                        HelpDetailRow(icon: "square.and.arrow.down", title: "Import/Export", subtitle: "Save your entire setup, including all profiles and shortcuts, to a file. Perfect for backups or moving to a new Mac.")
                    }
                }
                .padding()
            }
        }
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
    }
}

// MARK: - Reusable View Components
struct ProfileRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let profile: Profile
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(profile.name)
                .lineLimit(1)
                .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                .fontWeight(isSelected ? .semibold : .regular)
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.accentColor1(for: colorScheme))
                    .transition(.scale.animation(.spring()))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            (isSelected ? AppTheme.accentColor1(for: colorScheme).opacity(0.25) : AppTheme.pillBackgroundColor(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        )
    }
}

struct WelcomeActionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String; let title: String; let subtitle: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundColor(AppTheme.accentColor1(for: colorScheme)).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold).foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                Text(.init(subtitle)).font(.callout).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
            }
        }
    }
}

struct HelpDetailRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String; let title: String; let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title).foregroundColor(AppTheme.accentColor1(for: colorScheme)).frame(width: 40, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold).foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                Text(.init(subtitle)).font(.callout).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)).lineSpacing(4)
            }
        }
    }
}

struct CategoryHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let category: ShortcutCategory
    var body: some View {
        HStack {
            Image(systemName: category.systemImage)
            Text(category.rawValue)
            Spacer()
        }
        .font(.headline.weight(.bold))
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background {
            if colorScheme == .dark {
                AppTheme.background(for: .dark)
            } else {
                AppTheme.pillBackgroundColor(for: .light)
            }
        }
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .cornerRadius(8)
    }
}

struct ModifierKeySelector: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let isListening: Bool
    let keys: [ModifierKey]
    let onAdd: () -> Void
    let onRemove: (ModifierKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
            }
            
            HStack(spacing: 8) {
                if keys.isEmpty {
                    Text("No keys set")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                        .padding(.horizontal, 12)
                } else {
                    ForEach(keys) { key in
                        PillCard(content: {
                            HStack(spacing: 6) {
                                Text(key.displayName)
                                    .font(.system(.body, design: .monospaced).weight(.semibold))
                                    .lineLimit(1)
                                
                                Button(action: { onRemove(key) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                            }
                        }, cornerRadius: AppTheme.cornerRadius)
                    }
                }
                
                if isListening {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppTheme.accentColor1(for: colorScheme))
                        .frame(width: 20, height: 20)
                } else {
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppTheme.accentColor1(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}


struct EmptyStateView: View {
    @ObservedObject var manager: AppHotKeyManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    
    private var appTriggerString: String {
        manager.modifierKeyCombinationString(for: settings.currentProfile.wrappedValue.triggerModifiers[.app] ?? [])
    }
    
    private var secondaryTriggerString: String {
        manager.modifierKeyCombinationString(for: settings.currentProfile.wrappedValue.secondaryModifier)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles.square.filled.on.square")
                .font(.system(size: 50))
                .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                .opacity(0.8)
            VStack(spacing: 4) {
                Text("No Shortcuts Yet").font(.title3.weight(.bold))
                Text("Use the **+ Add Shortcut** button to begin\nor assign an app with **\(secondaryTriggerString) + \(appTriggerString) + [Letter]**")
                    .font(.callout).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)).multilineTextAlignment(.center).lineSpacing(4)
            }
            Spacer()
        }.padding().frame(maxWidth: .infinity)
    }
}

// MARK: - Assignment Row & Subviews
struct AssignmentRow: View {
    @ObservedObject var manager: AppHotKeyManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    
    let assignment: Assignment
    @Namespace private var pickerNamespace
    
    @State private var showingEditOptions = false
    @State private var sheetType: SheetType?
    
    private var isConflicting: Bool { manager.conflictingAssignmentIDs.contains(assignment.id) }
    
    private var isEditable: Bool {
        switch assignment.configuration.target {
        case .url, .script, .file:
            return true
        default:
            return false
        }
    }
    
    private var behaviorBinding: Binding<ShortcutConfiguration.Behavior> {
        Binding(
            get: { self.assignment.configuration.behavior },
            set: { newBehavior in
                if let index = settings.currentProfile.wrappedValue.assignments.firstIndex(where: { $0.id == assignment.id }) {
                    settings.currentProfile.wrappedValue.assignments[index].configuration.behavior = newBehavior
                }
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 15) {
                ShortcutIcon(target: assignment.configuration.target, manager: manager).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    ShortcutTitle(target: assignment.configuration.target, manager: manager)
                    ShortcutSubtitle(target: assignment.configuration.target)
                }
                Spacer()
                
                if let keyCode = assignment.keyCode {
                    let triggerKeys = settings.triggerModifiers(for: assignment.configuration.target)
                    let triggerString = manager.modifierKeyCombinationString(for: triggerKeys)
                    PillCard(content: { Text("\(triggerString) + \(manager.keyString(for: keyCode))").font(.system(.body, design: .monospaced).weight(.semibold)) }, cornerRadius: AppTheme.cornerRadius)
                } else {
                    Button(action: {
                        manager.listenForNewAssignment(target: assignment.configuration.target, assignmentID: assignment.id)
                    }) {
                        PillCard(content: {
                            Text("Set Hotkey")
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .foregroundColor(AppTheme.accentColor1(for: colorScheme))
                        }, cornerRadius: AppTheme.cornerRadius)
                    }.buttonStyle(.plain)
                }

                if isEditable {
                    Button(action: {
                        showingEditOptions = true
                    }) {
                        PillCard(content: { Image(systemName: "pencil.circle.fill").font(.system(.body, design: .monospaced).weight(.semibold)).foregroundColor(AppTheme.accentColor1(for: colorScheme)) }, cornerRadius: AppTheme.cornerRadius)
                    }.buttonStyle(.plain)
                }
                
                Button(action: { settings.currentProfile.wrappedValue.assignments.removeAll(where: { $0.id == assignment.id }) }) {
                    PillCard(content: { Image(systemName: "trash.fill").font(.system(.body, design: .monospaced).weight(.semibold)).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)) }, cornerRadius: AppTheme.cornerRadius)
                }.buttonStyle(.plain)
            }
            
            if isConflicting {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                    Text("Conflict detected").font(.callout).fontWeight(.semibold)
                    Spacer()
                    Button("Reassign...") {
                        manager.listenForNewAssignment(target: assignment.configuration.target, assignmentID: assignment.id)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(6)
            }
            
            if case .app = assignment.configuration.target {
                CustomSegmentedPicker(title: "Behavior Mode", selection: behaviorBinding, in: pickerNamespace)
            }
        }
        .padding(12).background(BlurredBackgroundView()).clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous).stroke(isConflicting ? Color.yellow : Color.primary.opacity(colorScheme == .dark ? 0.3 : 0.1), lineWidth: isConflicting ? 1.5 : 0.5))
        .animation(.easeInOut, value: isConflicting)
        .confirmationDialog("Edit Shortcut", isPresented: $showingEditOptions, titleVisibility: .visible) {
            Button("Change Hotkey") {
                manager.listenForNewAssignment(target: assignment.configuration.target, assignmentID: assignment.id)
            }
            Button("Edit Content") {
                switch assignment.configuration.target {
                case .url:
                    sheetType = .editURL(assignment: assignment)
                case .script:
                    sheetType = .editScript(assignment: assignment)
                case .file:
                    sheetType = .editFile(assignment: assignment)
                default:
                    break
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $sheetType) { item in
            switch item {
            case .editURL(let assignment):
                if case .url(let url) = assignment.configuration.target {
                    EditURLView(
                        assignmentID: assignment.id,
                        initialURL: url,
                        onSave: { id, newURL in
                            settings.updateAssignmentContent(id: id, newTarget: .url(newURL))
                        }
                    )
                }
            case .editScript(let assignment):
                if case .script(let command, let runsInTerminal) = assignment.configuration.target {
                    EditScriptView(
                        assignmentID: assignment.id,
                        initialCommand: command,
                        initialRunsInTerminal: runsInTerminal,
                        onSave: { id, newCommand, newRunsInTerminal in
                            settings.updateAssignmentContent(id: id, newTarget: .script(command: newCommand, runsInTerminal: newRunsInTerminal))
                        }
                    )
                }
            case .editFile(let assignment):
                EditFileView(
                    assignmentID: assignment.id,
                    onSave: { id, newPath in
                        settings.updateAssignmentContent(id: id, newTarget: .file(newPath))
                    }
                )
            default:
                EmptyView()
            }
        }
    }
}


struct ShortcutIcon: View {
    let target: ShortcutTarget
    @ObservedObject var manager: AppHotKeyManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        switch target {
        case .app(let bundleId): if let icon = manager.getAppIcon(for: bundleId) { Image(nsImage: icon).resizable() } else { Image(systemName: "app.dashed").font(.system(size: 28)) }
        case .url: Image(systemName: "globe").font(.system(size: 28)).foregroundColor(AppTheme.accentColor2(for: colorScheme))
        case .file: Image(systemName: "doc").font(.system(size: 28)).foregroundColor(AppTheme.accentColor2(for: colorScheme))
        case .script: Image(systemName: "terminal").font(.system(size: 28)).foregroundColor(AppTheme.accentColor2(for: colorScheme))
        case .shortcut: Image(systemName: "square.stack.3d.up.fill").font(.system(size: 28)).foregroundColor(AppTheme.accentColor2(for: colorScheme))
        }
    }
}

struct ShortcutTitle: View {
    let target: ShortcutTarget
    @ObservedObject var manager: AppHotKeyManager
    var body: some View {
        switch target {
        case .app(let bundleId): Text(manager.getAppName(for: bundleId) ?? "Unknown App").fontWeight(.semibold)
        case .url(let urlString): Text(URL(string: urlString)?.host ?? "Link").fontWeight(.semibold)
        case .file(let path): Text(URL(fileURLWithPath: path).lastPathComponent).fontWeight(.semibold)
        case .script: Text("Shell Script").fontWeight(.semibold)
        case .shortcut(let name): Text(name).fontWeight(.semibold)
        }
    }
}

struct ShortcutSubtitle: View {
    let target: ShortcutTarget
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let text: String = {
            switch target {
            case .app(let bundleId): return bundleId
            case .url(let urlString): return urlString
            case .file(let path): return path
            case .script(let command, _): return command
            case .shortcut: return "macOS Shortcut"
            }
        }()
        Text(text).font(.caption).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)).truncationMode(.middle).lineLimit(1)
    }
}

// MARK: - Add Shortcut Sheets
struct AddURLView: View {
    var onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var urlString = "https://"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add URL Shortcut").font(.title2.weight(.bold))
            URLTextField(text: $urlString)
                .frame(height: 22)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Next") {
                    if let url = URL(string: urlString), (url.scheme == "http" || url.scheme == "https") {
                        onSave(urlString)
                        dismiss()
                    }
                }.disabled(URL(string: urlString) == nil)
            }
        }.padding().frame(width: 350)
    }
}

struct EditURLView: View {
    let assignmentID: UUID
    let initialURL: String
    var onSave: (UUID, String) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var urlString: String

    init(assignmentID: UUID, initialURL: String, onSave: @escaping (UUID, String) -> Void) {
        self.assignmentID = assignmentID
        self.initialURL = initialURL
        self.onSave = onSave
        _urlString = State(initialValue: initialURL)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit URL Shortcut").font(.title2.weight(.bold))
            URLTextField(text: $urlString)
                .frame(height: 22)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    if let url = URL(string: urlString), (url.scheme == "http" || url.scheme == "https") {
                        onSave(assignmentID, urlString)
                        dismiss()
                    }
                }.disabled(URL(string: urlString) == nil)
            }
        }.padding().frame(width: 350)
    }
}

struct AddFileView: View {
    var onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add File/Folder Shortcut").font(.title2.weight(.bold))
            Text("Select a file or folder to create a shortcut.").multilineTextAlignment(.center).foregroundColor(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Select File/Folder...") {
                    let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true
                    if panel.runModal() == .OK, let url = panel.url { onSave(url.path); dismiss() }
                }
            }
        }.padding().frame(width: 350)
    }
}

struct EditFileView: View {
    let assignmentID: UUID
    var onSave: (UUID, String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Change File/Folder Shortcut").font(.title2.weight(.bold))
            Text("Select a new file or folder to update the shortcut.").multilineTextAlignment(.center).foregroundColor(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Select New File/Folder...") {
                    let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        onSave(assignmentID, url.path)
                        dismiss()
                    }
                }
            }
        }.padding().frame(width: 350)
    }
}

struct AddScriptView: View {
    var onSave: (String, Bool) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var command = ""
    @State private var runsInTerminal = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Script Shortcut").font(.title2.weight(.bold))
            Text("Enter a shell command to execute.").font(.caption).foregroundColor(.secondary)
            TextEditor(text: $command).font(.system(.body, design: .monospaced)).frame(height: 100).border(Color.secondary.opacity(0.5), width: 1).clipShape(RoundedRectangle(cornerRadius: 6))
            Toggle(isOn: $runsInTerminal) { Text("Show in a new Terminal window") }.toggleStyle(.checkbox)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }; Spacer()
                Button("Next") { onSave(command, runsInTerminal); dismiss() }.disabled(command.isEmpty)
            }
        }.padding().frame(width: 400)
    }
}

struct EditScriptView: View {
    let assignmentID: UUID
    var onSave: (UUID, String, Bool) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var command: String
    @State private var runsInTerminal: Bool

    init(assignmentID: UUID, initialCommand: String, initialRunsInTerminal: Bool, onSave: @escaping (UUID, String, Bool) -> Void) {
        self.assignmentID = assignmentID
        self.onSave = onSave
        _command = State(initialValue: initialCommand)
        _runsInTerminal = State(initialValue: initialRunsInTerminal)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Script Shortcut").font(.title2.weight(.bold))
            Text("Enter a shell command to execute.").font(.caption).foregroundColor(.secondary)
            TextEditor(text: $command).font(.system(.body, design: .monospaced)).frame(height: 100).border(Color.secondary.opacity(0.5), width: 1).clipShape(RoundedRectangle(cornerRadius: 6))
            Toggle(isOn: $runsInTerminal) { Text("Show in a new Terminal window") }.toggleStyle(.checkbox)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }; Spacer()
                Button("Save") { onSave(assignmentID, command, runsInTerminal); dismiss() }.disabled(command.isEmpty)
            }
        }.padding().frame(width: 400)
    }
}

struct ShortcutPickerView: View {
    var onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var allShortcuts: [String] = []
    @State private var searchText = ""
    @State private var isLoading = true

    private var filteredShortcuts: [String] {
        if searchText.isEmpty {
            return allShortcuts
        } else {
            return allShortcuts.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Select a macOS Shortcut")
                .font(.title2.weight(.bold))
                .padding()

            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                    Spacer()
                }
            } else if allShortcuts.isEmpty {
                VStack {
                    Spacer()
                    Text("No Shortcuts Found")
                        .foregroundColor(.secondary)
                    Text("Create shortcuts in the Shortcuts app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(filteredShortcuts, id: \.self) { shortcutName in
                    Button(action: {
                        onSave(shortcutName)
                        dismiss()
                    }) {
                        HStack {
                            Text(shortcutName)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search Shortcuts")
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            ShortcutRunner.getAllShortcutNames { names in
                self.allShortcuts = names.sorted()
                self.isLoading = false
            }
        }
    }
}

struct AppInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: NSImage

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct AppPickerView: View {
    var onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var allApps: [AppInfo] = []
    @State private var searchText = ""
    @State private var isLoading = true

    private var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return allApps
        } else {
            return allApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Select an Application")
                .font(.title2.weight(.bold))
                .padding()

            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                    Spacer()
                }
            } else if allApps.isEmpty {
                VStack {
                    Spacer()
                    Text("No Applications Found")
                        .foregroundColor(.secondary)
                    Text("Could not find any applications in standard directories.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(filteredApps, id: \.id) { app in
                    Button(action: {
                        onSave(app.id)
                        dismiss()
                    }) {
                        HStack(spacing: 12) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 32, height: 32)
                            Text(app.name)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search Applications")
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            loadApps()
        }
    }

    private func loadApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            var discoveredApps = [String: AppInfo]()
            let fileManager = FileManager.default
            let appDirectories = [
                "/Applications",
                "/System/Applications",
                "\(NSHomeDirectory())/Applications"
            ]

            for dirPath in appDirectories {
                let dirUrl = URL(fileURLWithPath: dirPath)
                if let urls = try? fileManager.contentsOfDirectory(at: dirUrl, includingPropertiesForKeys: [], options: .skipsHiddenFiles) {
                    for url in urls where url.pathExtension == "app" {
                        if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                            if discoveredApps[bundleId] == nil && !bundleId.starts(with: "com.apple.dt.") && bundleId != Bundle.main.bundleIdentifier {
                                let appName = (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String) ?? url.deletingPathExtension().lastPathComponent
                                let icon = NSWorkspace.shared.icon(forFile: url.path)
                                discoveredApps[bundleId] = AppInfo(id: bundleId, name: appName, icon: icon)
                            }
                        }
                    }
                }
            }
            
            let sortedApps = discoveredApps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            DispatchQueue.main.async {
                self.allApps = sortedApps
                self.isLoading = false
            }
        }
    }
}


// MARK: - Footer View
struct FooterView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isShowingClearConfirmation = false
    var onShowHelp: () -> Void
    var onShowAppSettings: () -> Void
    @Binding var sheetType: SheetType?
    private let donationURL = URL(string: "https://www.patreon.com/MusaMatini")!
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Menu {
                    Button("Add App") { sheetType = .addApp }
                    Button("Add macOS Shortcut") { sheetType = .addShortcut }
                    Button("Add URL") { sheetType = .addURL }
                    Button("Add File/Folder") { sheetType = .addFile }
                    Button("Add Script") { sheetType = .addScript }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .foregroundColor(AppTheme.accentColor1(for: colorScheme))
                            .font(.system(size: 16, weight: .semibold))
                        Text("Add Shortcut")
                    }
                }
                Spacer()
                Button(action: onShowAppSettings) {
                    HStack(spacing: 8) {
                        Text("App Settings")
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(AppTheme.accentColor1(for: colorScheme))
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            Divider().blendMode(.overlay)
            HStack {
                Button(action: onShowHelp) {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(AppTheme.accentColor1(for: colorScheme))
                            .font(.system(size: 16, weight: .semibold))
                        Text("How to Use")
                    }
                }
                Spacer()
                Link(destination: donationURL) {
                    HStack(spacing: 8) {
                        Text("Support Me")
                        Image(systemName: "heart.circle.fill")
                            .foregroundColor(AppTheme.accentColor1(for: colorScheme))
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            Divider().blendMode(.overlay)
            HStack {
                Button("Clear Profile Shortcuts", role: .destructive) {
                    isShowingClearConfirmation = true
                }.disabled(settings.currentProfile.wrappedValue.assignments.isEmpty)
                Spacer()
                Button("Quit WrapKey") { NSApplication.shared.terminate(nil) }
            }
        }
        .font(.body).buttonStyle(.plain).foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .padding(16).background(
            ZStack {
                if colorScheme == .light {
                    AppTheme.cardBackgroundColor(for: .light)
                } else {
                    VisualEffectBlur()
                }
            }
            .overlay(Color.black.opacity(colorScheme == .dark ? 0.1 : 0))
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous).stroke(Color.primary.opacity(colorScheme == .dark ? 0.3 : 0.1), lineWidth: 0.7))
        .padding(.horizontal, 10).padding(.bottom, 10).padding(.top, -134)
        .alert("Clear All Shortcuts in Profile?", isPresented: $isShowingClearConfirmation) {
            Button("Clear \"\(settings.currentProfile.wrappedValue.name)\"", role: .destructive) { settings.currentProfile.wrappedValue.assignments.removeAll() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This will remove all shortcuts from the currently selected profile. This cannot be undone.") }
    }
}

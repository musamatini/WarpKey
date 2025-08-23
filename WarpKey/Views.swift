//Views.swift

import SwiftUI
import AppKit
import Sparkle
import Combine

struct AppInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let icon: NSImage
}

struct AppScanner {
    static func getAllApps(completion: @escaping ([AppInfo]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var applications = [AppInfo]()
            var seenBundleIDs = Set<String>()

            let fileManager = FileManager.default
            let domains: [FileManager.SearchPathDomainMask] = [.systemDomainMask, .localDomainMask, .userDomainMask]
            
            for domain in domains {
                let appDirs = NSSearchPathForDirectoriesInDomains(.applicationDirectory, domain, true)
                for appDir in appDirs {
                    guard let enumerator = fileManager.enumerator(
                        at: URL(fileURLWithPath: appDir),
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else { continue }

                    for case let url as URL in enumerator {
                        if url.pathExtension == "app" {
                            guard let bundle = Bundle(url: url),
                                  let bundleId = bundle.bundleIdentifier,
                                  !seenBundleIDs.contains(bundleId) else { continue }

                            var appName = fileManager.displayName(atPath: url.path)
                            if appName.hasSuffix(".app") {
                                appName = String(appName.dropLast(4))
                            }
                            
                            let icon = NSWorkspace.shared.icon(forFile: url.path)
                            
                            applications.append(AppInfo(id: bundleId, name: appName, url: url, icon: icon))
                            seenBundleIDs.insert(bundleId)
                        }
                    }
                }
            }
            
            let finderBundleId = "com.apple.finder"
            if !seenBundleIDs.contains(finderBundleId), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: finderBundleId) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                applications.append(AppInfo(id: finderBundleId, name: "Finder", url: url, icon: icon))
                seenBundleIDs.insert(finderBundleId)
            }
            
            DispatchQueue.main.async {
                completion(applications.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
        }
    }
}

enum SheetType: Identifiable, Equatable {
    case addApp, addShortcut, addURL, addScript, addSnippet
    case edit(assignment: Assignment)

    var id: String {
        switch self {
        case .addApp: "addApp"
        case .addShortcut: "addShortcut"
        case .addURL: "addURL"
        case .addScript: "addScript"
        case .addSnippet: "addSnippet"
        case .edit(let a): "edit-\(a.id)"
        }
    }
}

enum AppPage: Hashable {
    case welcome, main, help, appSettings
}

struct SheetContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(VisualEffectBlur())
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .shadow(radius: 20)
            .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Permission Views

struct PermissionWarningView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let message: String
    let buttonText: String
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.bold)
                Text(message)
                    .font(.callout)
                    .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
            }
            
            Spacer()
            
            Button(action: action) {
                Text(buttonText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(12)
        .background(Color.yellow.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

struct ScreenRecordingPermissionRequiredView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 35) {
                VStack(spacing: 15) {
                    Image(systemName: "rectangle.on.rectangle.angled.fill")
                        .font(.system(size: 50, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                    
                    Text("Enhanced Window Switching")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
                
                VStack(spacing: 12) {
                    Text("To switch to apps on other desktops or in fullscreen, WarpKey needs Screen Recording permission.")
                    
                    Text("**WarpKey never records your screen.** macOS bundles this permission with the ability to see windows across all spaces.")
                        .font(.footnote)
                        .padding(10)
                        .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme))
                        .cornerRadius(AppTheme.cornerRadius)
                    
                    Text("1. Click **Open System Settings**.\n2. Find **WarpKey** in the list and turn it on.\n3. Relaunch the app if prompted.")
                }
                .font(.callout)
                .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 40)
            }
            Spacer()
            VStack(spacing: 16) {
                Button(action: { AccessibilityManager.requestScreenRecordingPermissions() }) {
                    Text("Open System Settings")
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 40).padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(AppTheme.adaptiveTextColor(on: AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)))
                        .background(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                        .cornerRadius(50)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o", modifiers: [])
                
                Button(action: { NotificationCenter.default.post(name: .requestAppRestart, object: nil) }) {
                    Text("Relaunch App")
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                        .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme))
                        .cornerRadius(50)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: [])
                
                Button(action: { settings.hasSkippedScreenRecordingPermission = true }) {
                    Text("Continue without this feature")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                
            }
            .padding(.horizontal, 50)
            .padding(.bottom, 50)
        }
        .background(AppTheme.background(for: colorScheme, theme: settings.appTheme).ignoresSafeArea())
    }
}

struct MenuView: View {
    @ObservedObject var manager: AppHotKeyManager
    @ObservedObject var launchManager: LaunchAtLoginManager
    @ObservedObject var updaterViewModel: UpdaterViewModel
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentPage: AppPage = .main

    var body: some View {
        ZStack {
            if !settings.hasCompletedOnboarding {
                WelcomePage(
                    manager: manager,
                    onGetStarted: {
                        if !manager.hasAccessibilityPermissions {
                            AccessibilityManager.requestPermissions()
                        }
                        settings.hasCompletedOnboarding = true
                    },
                    onGoToHelp: { settings.hasCompletedOnboarding = true; currentPage = .help }
                )
            } else if !manager.hasAccessibilityPermissions {
                PermissionsRestartRequiredView()
            } else if !manager.hasScreenRecordingPermissions && !settings.hasSkippedScreenRecordingPermission {
                ScreenRecordingPermissionRequiredView()
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
        .animation(.default, value: manager.hasAccessibilityPermissions)
        .animation(.default, value: settings.hasCompletedOnboarding)
        .animation(.default, value: manager.hasScreenRecordingPermissions)
        .animation(.default, value: settings.hasSkippedScreenRecordingPermission)
        .overlay(
            Group {
                if manager.recordingState != nil {
                     Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture { manager.cancelRecording() }
                        .transition(.opacity)

                    ShortcutRecordingView(manager: manager, isFloating: manager.recordingState?.isFloating ?? false)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.recordingState != nil)
        )
    }
}

struct MainTabView: View {
    @ObservedObject var manager: AppHotKeyManager
    @ObservedObject var launchManager: LaunchAtLoginManager
    @ObservedObject var updaterViewModel: UpdaterViewModel
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var selectedTab: AppPage
    private let githubURL = URL(string: "https://github.com/musamatini/WarpKey")!

    init(manager: AppHotKeyManager, launchManager: LaunchAtLoginManager, updaterViewModel: UpdaterViewModel, initialTab: AppPage) {
        self.manager = manager
        self.launchManager = launchManager
        self.updaterViewModel = updaterViewModel
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme, theme: settings.appTheme).ignoresSafeArea()
            
            VStack {
                switch selectedTab {
                case .main:
                    MainSettingsView(manager: manager, showHelpPage: { selectedTab = .help }, showAppSettingsPage: { selectedTab = .appSettings })
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                case .help:
                    HelpView(goBack: { selectedTab = .main })
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                case .appSettings:
                    AppSettingsView(
                        launchManager: launchManager,
                        updaterViewModel: updaterViewModel,
                        manager: manager,
                        goBack: { selectedTab = .main }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                case .welcome: EmptyView()
                }
            }
            
            VStack {
                ZStack {
                    AppTheme.background(for: colorScheme, theme: settings.appTheme)
                    Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05)
                }
                .frame(height: 37)
                .ignoresSafeArea(.container, edges: .top)
                
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .animation(.interpolatingSpring(stiffness: 600, damping: 40), value: selectedTab)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if selectedTab == .help || selectedTab == .appSettings {
                    Button(action: { selectedTab = .main }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            KeyboardHint(key: "⌫")
                        }
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                }
            }

            ToolbarItemGroup(placement: .principal) {
                switch selectedTab {
                case .main:
                    HStack(spacing: 4) {
                        if let appIcon = NSImage(named: NSImage.Name("AppIcon")) {
                            Image(nsImage: appIcon)
                                .resizable().aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius - 1, style: .continuous))
                        }
                        Button(action: { openURL(githubURL) }) {
                             HStack {
                                Text("WarpKey").font(.headline).fontWeight(.semibold)
                                KeyboardHint(key: "G")
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                        .keyboardShortcut("g", modifiers: [])
                    }
                case .help:
                    Text("How to Use").font(.headline)
                case .appSettings:
                    Text("WarpKey Settings").font(.headline)
                case .welcome:
                    EmptyView()
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                 if selectedTab == .main {
                    ProfileDropdownButton()
                 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goToHelpPageInMainWindow)) { _ in
            selectedTab = .help
        }
        .onReceive(NotificationCenter.default.publisher(for: .goToSettingsPageInMainWindow)) { _ in
                selectedTab = .appSettings
        }
    }
}

struct MainSettingsView: View {
    @ObservedObject var manager: AppHotKeyManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    var showHelpPage: () -> Void
    var showAppSettingsPage: () -> Void

    @State private var showingSheet: SheetType?
    @State private var assignmentForEditOptions: Assignment?
    @State private var isShowingEditOptionsDialog = false

    private var categorizedAssignments: [ShortcutCategory: [Assignment]] {
        Dictionary(grouping: settings.currentProfile.wrappedValue.assignments) { $0.configuration.target.category }
    }
    private let categoryOrder: [ShortcutCategory] = [.app, .snippet, .shortcut, .url, .file, .script]
    
    private func editButtonTitle(for target: ShortcutTarget) -> String {
        switch target {
        case .app, .shortcut:
            return "Edit Name"
        case .url, .script, .file, .snippet:
            return "Edit Details"
        }
    }
    
    private func handleAddFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let name = url.lastPathComponent
            let target = ShortcutTarget.file(name: name, path: url.path)
            manager.startRecording(for: .create(target: target))
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 18, pinnedViews: .sectionHeaders) {
                if settings.currentProfile.wrappedValue.assignments.isEmpty {
                    EmptyStateView()
                } else {
                    ForEach(categoryOrder, id: \.self) { category in
                        if let items = categorizedAssignments[category]?.sorted(by: { $0.configuration.target.displayName < $1.configuration.target.displayName }), !items.isEmpty {
                            Section(header: CategoryHeader(category: category)) {
                                ForEach(items) { assignment in
                                    AssignmentRow(
                                        manager: manager,
                                        assignment: assignment,
                                        onShowEditOptions: {
                                            self.assignmentForEditOptions = assignment
                                            self.isShowingEditOptionsDialog = true
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                Spacer().frame(height: 133)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
        }
        .safeAreaInset(edge: .bottom) {
            FooterView(onShowHelp: showHelpPage, onShowAppSettings: showAppSettingsPage, onAddFile: handleAddFile, sheetType: $showingSheet)
                .environmentObject(manager)
        }
                .customSheet(
            isPresented: Binding(
                get: { showingSheet != nil },
                set: { if !$0 { showingSheet = nil } }
            ),
            animated: true
        ) {
            switch showingSheet {
            case .addApp:
                AddAppView(onSave: { name, bundleId in
                    let target = ShortcutTarget.app(name: name, bundleId: bundleId)
                    manager.startRecording(for: .create(target: target))
                    showingSheet = nil
                }, showingSheet: $showingSheet)
            case .addShortcut:
                ShortcutPickerView(onSave: { name in
                    let target = ShortcutTarget.shortcut(name: name, executionName: name)
                    manager.startRecording(for: .create(target: target))
                    showingSheet = nil
                }, showingSheet: $showingSheet)
            case .addURL:
                AddURLView(onSave: { url in
                    let name = URL(string: url)?.host ?? "Link"
                    let target = ShortcutTarget.url(name: name, address: url)
                    manager.startRecording(for: .create(target: target))
                    showingSheet = nil
                }, showingSheet: $showingSheet)
            case .addScript:
                AddScriptView(onSave: { name, command, runsInTerminal in
                    let target = ShortcutTarget.script(name: name, command: command, runsInTerminal: runsInTerminal)
                    manager.startRecording(for: .create(target: target))
                    showingSheet = nil
                }, showingSheet: $showingSheet)
            case .addSnippet:
                AddSnippetView(onSave: { name, content in
                    let target = ShortcutTarget.snippet(name: name, content: content)
                    manager.startRecording(for: .create(target: target))
                    showingSheet = nil
                }, showingSheet: $showingSheet)
            case .edit(let assignment):
                EditView(
                    assignment: assignment,
                    isPresented: Binding(get: { self.showingSheet != nil }, set: { if !$0 { self.showingSheet = nil } })
                )
            case .none:
                EmptyView()
            }
        }
        .id(showingSheet?.id)
        .confirmationDialog("Edit Shortcut", isPresented: $isShowingEditOptionsDialog, titleVisibility: .visible) {
            if let assignment = assignmentForEditOptions {
                Button("Change Hotkey") {
                    manager.startRecording(for: .edit(assignmentID: assignment.id, target: assignment.configuration.target))
                }
                
                Button(editButtonTitle(for: assignment.configuration.target)) {
                    self.showingSheet = .edit(assignment: assignment)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

struct AppSettingsView: View {
    @ObservedObject var launchManager: LaunchAtLoginManager
    @ObservedObject var updaterViewModel: UpdaterViewModel
    @ObservedObject var manager: AppHotKeyManager

    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    var goBack: () -> Void

    @State private var isShowingProfileNameAlert = false
    @State private var isShowingDeleteProfileAlert = false
    @State private var isEditingExistingProfile = false
    @State private var profileToDelete: Profile?
    @State private var profileNameField = ""
    private let authorURL = URL(string: "https://musa.matini.link")!

    @Namespace private var appearancePickerNamespace

    private let themeColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 28), spacing: 12)
    ]

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "N/A"
        return "\(version) (build \(build))"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if !manager.hasScreenRecordingPermissions && settings.hasSkippedScreenRecordingPermission {
                PermissionWarningView(
                    title: "Enhanced Switching Disabled",
                    message: "WarpKey can't switch to fullscreen or cross-space apps without Screen Recording permission.",
                    buttonText: "Enable",
                    action: { AccessibilityManager.requestScreenRecordingPermissions() }
                )
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            VStack(alignment: .leading, spacing: 20) {
                
                HelpSection(title: "General") {
                    Toggle("Show Menu Bar Icon", isOn: $settings.showMenuBarIcon)
                        .toggleStyle(CustomSwitchToggleStyle())
                    Toggle("Launch at Login", isOn: $launchManager.isEnabled)
                        .toggleStyle(CustomSwitchToggleStyle())
                }

                HelpSection(title: "Appearance") {
                    VStack(alignment: .leading, spacing: 15) {
                        CustomSegmentedPicker(title: "Mode", selection: $settings.colorScheme, in: appearancePickerNamespace, showKeyboardHints: false)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Theme")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                            
                            LazyVGrid(columns: themeColumns, spacing: 12) {
                                ForEach(Theme.allCases) { theme in
                                    Circle()
                                        .fill(AppTheme.accentColor1(for: colorScheme, theme: theme))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .stroke(AppTheme.accentColor2(for: colorScheme, theme: settings.appTheme), lineWidth: settings.appTheme == theme ? 3 : 0)
                                        )
                                        .onTapGesture {
                                            withAnimation(.spring()) {
                                                settings.appTheme = theme
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
                
                HelpSection(title: "Cheatsheet") {
                    Text("Hold a global hotkey to quickly see all of your assigned shortcuts for the current profile.")
                        .font(.callout)
                        .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                    
                    VStack(spacing: 8) {
                        PillCard(content: {
                            HStack {
                                Text("Cheatsheet Hotkey")
                                Spacer()
                                Text(manager.shortcutKeyCombinationString(for: settings.cheatsheetShortcut.keys))
                                            .font(.system(.body, design: .monospaced))
                            }
                        }, cornerRadius: AppTheme.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                                .stroke(manager.isCheatsheetConflicting ? Color.yellow : Color.clear, lineWidth: 1.5)
                        )

                        if manager.isCheatsheetConflicting {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                                Text("This hotkey conflicts with another shortcut.").font(.caption).fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Color.yellow.opacity(0.2)).cornerRadius(AppTheme.cornerRadius)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                        }
                    }
                    .animation(.default, value: manager.isCheatsheetConflicting)

                    HStack(spacing: 10) {
                        Button("Set Shortcut") { manager.startRecording(for: .cheatsheet) }
                        Button("Clear") { settings.cheatsheetShortcut = SpecialShortcut(keys: [], trigger: .press) }
                            .disabled(settings.cheatsheetShortcut.keys.isEmpty)
                    }
                    .buttonStyle(PillButtonStyle())
                }

                HelpSection(title: "Quick Assign") {
                    Text("Hold a global hotkey to assign a new shortcut to the currently focused application.")
                        .font(.callout)
                        .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))

                    VStack(spacing: 8) {
                        PillCard(content: {
                            HStack {
                                Text("Quick Assign Hotkey")
                                Spacer()
                                SpecialShortcutDisplay(shortcut: settings.appAssigningShortcut, manager: manager)
                            }
                        }, cornerRadius: AppTheme.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                                .stroke(manager.isQuickAssignConflicting ? Color.yellow : Color.clear, lineWidth: 1.5)
                        )

                        if manager.isQuickAssignConflicting {
                             HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                                Text("This hotkey conflicts with another shortcut.").font(.caption).fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Color.yellow.opacity(0.2)).cornerRadius(AppTheme.cornerRadius)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                        }
                    }
                    .animation(.default, value: manager.isQuickAssignConflicting)

                    HStack(spacing: 10) {
                        Button("Set Shortcut") { manager.startRecording(for: .quickAssign) }
                        Button("Clear") { settings.appAssigningShortcut = SpecialShortcut(keys: [], trigger: .press) }
                            .disabled(settings.appAssigningShortcut.keys.isEmpty)
                    }
                    .buttonStyle(PillButtonStyle())
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
                            profileNameField = ""; isEditingExistingProfile = false; isShowingProfileNameAlert = true
                        }
                        
                        Button("Rename") {
                            profileNameField = settings.currentProfile.wrappedValue.name; isEditingExistingProfile = true; isShowingProfileNameAlert = true
                        }
                        
                        Button(action: {
                            profileToDelete = settings.currentProfile.wrappedValue; isShowingDeleteProfileAlert = true
                        }) {
                            Text("Delete")
                                .foregroundColor(settings.profiles.count <= 1 ? .secondary : .red.opacity(0.9))
                        }
                        .disabled(settings.profiles.count <= 1)
                    }
                    .buttonStyle(PillButtonStyle())
                }
                
                HelpSection(title: "Data Management") {
                    HStack(spacing: 10) {
                        Button("Import All Profiles...") { importSettings() }
                        Button("Export All Profiles...") { exportSettings() }
                    }
                    .buttonStyle(PillButtonStyle())
                }
                
                HelpSection(title: "Updates") {
                    Toggle("Check for updates automatically", isOn: $updaterViewModel.automaticallyChecksForUpdates)
                        .toggleStyle(CustomSwitchToggleStyle())
                    Divider().padding(.vertical, 4)
                    Button("Check for Updates Now") { updaterViewModel.checkForUpdates() }
                        .buttonStyle(PillButtonStyle())
                        .disabled(!updaterViewModel.canCheckForUpdates)
                }
                
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        Text("Made with "); Text(Image(systemName: "heart.fill")).foregroundColor(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)); Text(" by ")
                        Link("Musa Matini", destination: authorURL).buttonStyle(.plain).foregroundColor(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                    }
                    Text("WarpKey Version \(appVersion)")
                }
                .font(.caption).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)).frame(maxWidth: .infinity, alignment: .center).padding(.top, 3)
            }
            .padding(16)
        }
        .animation(.default, value: manager.hasScreenRecordingPermissions)
        .animation(.default, value: settings.hasSkippedScreenRecordingPermission)
        .alert(isEditingExistingProfile ? "Rename Profile" : "New Profile", isPresented: $isShowingProfileNameAlert) {
            TextField("Profile Name", text: $profileNameField)
            Button("Save") {
                if isEditingExistingProfile { settings.currentProfile.wrappedValue.name = profileNameField }
                else { settings.addNewProfile(name: profileNameField.isEmpty ? "New Profile" : profileNameField) }
            }.keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.cancelAction)
        }
        .alert("Delete Profile", isPresented: $isShowingDeleteProfileAlert, presenting: profileToDelete) { profile in
            Button("Delete \"\(profile.name)\"", role: .destructive) { settings.deleteProfile(id: profile.id) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.cancelAction)
        }
    }

    private func exportSettings() {
        let savePanel = NSSavePanel(); savePanel.allowedContentTypes = [.json]; savePanel.nameFieldStringValue = "WarpKey_Settings.json"
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
                let importedProfiles = try JSONDecoder().decode([Profile].self, from: data)

                var validShortcutsCount = 0; var skippedShortcutsCount = 0
                let validatedProfiles = importedProfiles.map { profile -> Profile in
                    var newProfile = profile; var validatedAssignments: [Assignment] = []
                    for assignment in profile.assignments {
                        if case .app(_, let bundleId) = assignment.configuration.target {
                            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
                                validatedAssignments.append(assignment); validShortcutsCount += 1
                            } else { skippedShortcutsCount += 1 }
                        } else { validatedAssignments.append(assignment); validShortcutsCount += 1 }
                    }
                    newProfile.assignments = validatedAssignments; return newProfile
                }
                settings.profiles = validatedProfiles; settings.currentProfileID = validatedProfiles.first?.id ?? UUID()
                NotificationManager.shared.sendNotification(title: "Import Complete", body: "\(validShortcutsCount) shortcuts imported. \(skippedShortcutsCount) for missing apps were skipped.")
            } catch { NotificationManager.shared.sendNotification(title: "Import Failed", body: "The selected file is not a valid WarpKey settings file.") }
        }
    }
}

struct SpecialShortcutDisplay: View {
    let shortcut: SpecialShortcut
    let manager: AppHotKeyManager
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        HStack {
            if shortcut.trigger != .press {
                Text(shortcut.trigger.abbreviation)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
            }
            Text(manager.shortcutKeyCombinationString(for: shortcut.keys))
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct CheatsheetView: View {
    @ObservedObject var manager: AppHotKeyManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    private var allAssignments: [Assignment] {
        settings.currentProfile.wrappedValue.assignments.filter { !$0.shortcut.isEmpty }
    }

    private var categorizedAssignments: [ShortcutCategory: [Assignment]] {
        Dictionary(grouping: allAssignments) { $0.configuration.target.category }
    }

    private let categoryOrder: [ShortcutCategory] = [.app, .shortcut, .url, .file, .script]

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 250), spacing: 16)
    ]

    private func hide() {
        NotificationCenter.default.post(name: .hideCheatsheet, object: nil)
    }

    var body: some View {
        ZStack {
            VisualEffectBlur()
                .onTapGesture { hide() }

            VStack(spacing: 0) {
                Text("WarpKey Shortcuts Cheatsheet")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .padding()
                
                Text("Profile: \(settings.currentProfile.wrappedValue.name)")
                    .font(.headline)
                    .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                    .padding(.bottom)
                
                if allAssignments.isEmpty {
                    Spacer()
                    Text("No shortcuts assigned in this profile.")
                        .font(.title3)
                        .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(categoryOrder, id: \.self) { category in
                                if let items = categorizedAssignments[category]?.sorted(by: { $0.configuration.target.displayName < $1.configuration.target.displayName }), !items.isEmpty {
                                    
                                    Text(category.rawValue)
                                        .font(.title3.weight(.bold))
                                        .padding(.bottom, 4)
                                        .padding(.top, 20)

                                    LazyVGrid(columns: columns, spacing: 12) {
                                        ForEach(items) { assignment in
                                            HStack(spacing: 12) {
                                                ShortcutIcon(target: assignment.configuration.target, manager: manager)
                                                    .frame(width: 28, height: 28)
                                                ShortcutTitle(target: assignment.configuration.target)
                                                Spacer()
                                                
                                                PillCard(content: {
                                                    HStack {
                                                        if assignment.trigger != .press {
                                                            Text(assignment.trigger.abbreviation)
                                                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                                                .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                                                        }
                                                        Text(manager.shortcutKeyCombinationString(for: assignment.shortcut))
                                                            .font(.system(.body, design: .monospaced).weight(.semibold))
                                                    }
                                                }, cornerRadius: AppTheme.cornerRadius)
                                            }
                                            .padding(12)
                                            .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme))
                                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(40)
            .focusable()
            .onExitCommand {
                hide()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius * 2, style: .continuous))
    }
}

struct PermissionsRestartRequiredView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 35) {
                VStack(spacing: 15) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 50, weight: .bold)).symbolRenderingMode(.monochrome).foregroundStyle(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                    Text("Accessibility Access Required").font(.system(size: 28, weight: .bold, design: .rounded))
                }
                Text("WarpKey needs your permission to listen for keyboard events.\n\n1. Click **Open System Settings**.\n2. Find **WarpKey** in the list and turn it on.\n3. Return here and click **Relaunch App**.")
                    .font(.callout).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)).multilineTextAlignment(.center).lineSpacing(5).padding(.horizontal, 40)
            }
            Spacer()
            VStack(spacing: 16) {
                Button(action: { AccessibilityManager.requestPermissions() }) {
                    Text("Open System Settings")
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 40).padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(AppTheme.adaptiveTextColor(on: AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)))
                        .background(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                        .cornerRadius(50)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o", modifiers: [])
                
                Button(action: { NotificationCenter.default.post(name: .requestAppRestart, object: nil) }) {
                    Text("Relaunch App").font(.headline.weight(.semibold)).padding(.horizontal, 40).padding(.vertical, 14).frame(maxWidth: .infinity).foregroundColor(AppTheme.primaryTextColor(for: colorScheme)).background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme)).cornerRadius(50)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: [])
            }.padding(.horizontal, 50).padding(.bottom, 50)
        }
        .background(AppTheme.background(for: colorScheme, theme: settings.appTheme).ignoresSafeArea())
    }
}

struct PermissionsAlertView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 25) {
            Image(systemName: "exclamationmark.lock.fill")
                .font(.system(size: 40, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.yellow)
            
            VStack(spacing: 10) {
                Text("Permissions Revoked")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text("WarpKey's Accessibility permissions were revoked. To prevent system instability, shortcut monitoring has been stopped. Please re-grant permissions and relaunch the app.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit App")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut("q", modifiers: [])
                
                Button(action: {
                    AccessibilityManager.requestPermissions()
                }) {
                    Text("Open System Settings")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(AppTheme.adaptiveTextColor(on: AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)))
                        .background(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o", modifiers: [])
            }
        }
        .padding(25)
        .frame(width: 380)
        .background(VisualEffectBlur())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius * 2, style: .continuous))
        .shadow(radius: 20)
    }
}

struct WelcomePage: View {
    @ObservedObject var manager: AppHotKeyManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    var onGetStarted: () -> Void
    var onGoToHelp: () -> Void

    @State private var isShowingContent = false
    private let donationURL = URL(string: "https://www.patreon.com/MusaMatini")!
    private let githubURL = URL(string: "https://github.com/musamatini/WarpKey")!

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            VStack(spacing: 35) {
                VStack(spacing: 15) {
                    Image(systemName: "sparkles").font(.system(size: 50, weight: .bold)).symbolRenderingMode(.monochrome).foregroundStyle(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                    Text("Welcome to WarpKey").font(.system(size: 32, weight: .bold, design: .rounded))
                }.opacity(isShowingContent ? 1 : 0).animation(.easeInOut(duration: 0.7), value: isShowingContent)
                
                VStack(alignment: .leading, spacing: 25) {
                    WelcomeActionRow(icon: "plus.app.fill", title: "Add a Shortcut", subtitle: "Use the **+ Add Shortcut** button in the main window.")
                    WelcomeActionRow(icon: "pencil.and.ruler.fill", title: "Set Your Hotkey", subtitle: "After adding a shortcut, a recorder will appear. Press any key combination you want.")
                    WelcomeActionRow(icon: "bolt.horizontal.circle.fill", title: "Use Your Shortcut", subtitle: "Press your new hotkey anywhere in macOS to launch or switch to your app.")
                }.padding(.horizontal, 40).opacity(isShowingContent ? 1 : 0).animation(.easeInOut(duration: 0.7).delay(0.1), value: isShowingContent)
                
                (Text("Check the ") + Text("How to Use").bold().foregroundColor(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)).underline() + Text(" page for more info."))
                    .font(.callout).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)).multilineTextAlignment(.center).lineSpacing(5)
                    .onTapGesture { onGoToHelp() }
                    .opacity(isShowingContent ? 1 : 0).animation(.easeInOut(duration: 0.7).delay(0.2), value: isShowingContent)
                
                VStack(spacing: 18) {
                    Link(destination: githubURL) { HStack(spacing: 8) { Image(systemName: "ant.circle.fill"); Text("Report a bug or suggest a feature") } }
                    Link(destination: donationURL) { HStack(spacing: 8) { Image(systemName: "heart.circle.fill"); Text("Support the project") } }
                }.font(.callout).buttonStyle(.plain).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme).opacity(0.8))
                 .opacity(isShowingContent ? 1 : 0).animation(.easeInOut(duration: 0.7).delay(0.3), value: isShowingContent)
            }
            Spacer()
            Button(action: onGetStarted) {
                Text("Continue to App")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 40).padding(.vertical, 14)
                    .foregroundColor(AppTheme.adaptiveTextColor(on: AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)))
                    .background(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                    .cornerRadius(50)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .opacity(isShowingContent ? 1 : 0).animation(.easeInOut(duration: 0.7).delay(0.4), value: isShowingContent).padding(.bottom, 50)
        }
        .background(AppTheme.background(for: colorScheme, theme: settings.appTheme).ignoresSafeArea())
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.isShowingContent = true } }
    }
}

struct HelpView: View {
    @EnvironmentObject var settings: SettingsManager
    var goBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                
                HelpSection(title: "Core Actions") {
                    HelpDetailRow(icon: "plus", title: "Add Any Shortcut", subtitle: "Use the **+ Add Shortcut** button to create shortcuts for Apps, URLs, Files, Scripts, and macOS Shortcuts.")
                    HelpDetailRow(icon: "keyboard.fill", title: "Record a Hotkey", subtitle: "After adding a new item, the hotkey recorder will appear. Press and hold your desired key combination, then release to set it.")
                    HelpDetailRow(icon: "pencil", title: "Edit a Hotkey", subtitle: "Click the pencil icon on any shortcut. The recorder will show the current hotkey. Press a new combination to overwrite it, or click Done to keep it.")
                    HelpDetailRow(icon: "bolt.circle.fill", title: "Trigger a Shortcut", subtitle: "Press the assigned hotkey anywhere in macOS to run the action. This will launch, hide, or cycle an app's windows.")
                }
                
                HelpSection(title: "Shortcut Types") {
                    HelpDetailRow(icon: "app.dashed", title: "Apps", subtitle: "Launches, hides, or cycles windows of an application.")
                    HelpDetailRow(icon: "square.stack.3d.up.fill", title: "macOS Shortcuts", subtitle: "Runs a shortcut from Apple's Shortcuts app by its exact name.")
                    HelpDetailRow(icon: "globe", title: "URLs", subtitle: "Opens the web address in your default browser.")
                    HelpDetailRow(icon: "doc", title: "Files & Folders", subtitle: "Opens the selected file with its default app, or opens the folder in Finder.")
                    HelpDetailRow(icon: "terminal", title: "Scripts", subtitle: "Executes a shell command, either silently or in a new Terminal window.")
                }
                
                HelpSection(title: "Advanced Features") {
                    HelpDetailRow(icon: "keyboard.onehanded.left.fill", title: "Complex Hotkeys", subtitle: "Assign any combination of keys, like **⌃ + ⌥ + P**, as a hotkey. Modifier keys and one character key are recommended.")
                    HelpDetailRow(icon: "cursorarrow.click.badge.clock", title: "Advanced Triggers", subtitle: "Use the dropdown in the recorder to assign actions to a **Press**, **Double Press**, **Triple Press**, or a long **Hold**. Two shortcuts with the same keys but different triggers can coexist.")
                    HelpDetailRow(icon: "person.2.fill", title: "Profiles", subtitle: "Create different sets of shortcuts for different contexts (e.g., 'Work', 'Gaming'). Manage them in App Settings.")
                    HelpDetailRow(icon: "exclamationmark.triangle.fill", title: "Hotkey Conflicts", subtitle: "If a hotkey is assigned to multiple actions with the same trigger type, a warning will appear. When pressed, all conflicting actions will run.")
                    HelpDetailRow(icon: "square.and.arrow.down", title: "Import/Export", subtitle: "Save your entire setup to a file. Perfect for backups or moving to a new Mac.")
                }
            }
            .padding(16)
        }
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
    }
}

struct ProfileRowView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    let profile: Profile
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(profile.name).lineLimit(1).foregroundColor(AppTheme.primaryTextColor(for: colorScheme)).fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundColor(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)).transition(.scale.animation(.spring()))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background((isSelected ? AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme).opacity(0.25) : AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme)).clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)))
    }
}

struct WelcomeActionRow: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    let icon: String; let title: String; let subtitle: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundColor(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold).foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                Text(.init(subtitle)).font(.callout).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
            }
        }
    }
}

struct HelpDetailRow: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    let icon: String; let title: String; let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title).foregroundColor(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)).frame(width: 40, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold).foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                Text(.init(subtitle)).font(.callout).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)).lineSpacing(4)
            }
        }
    }
}

struct CategoryHeader: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    let category: ShortcutCategory

    var body: some View {
        HStack {
            Image(systemName: category.systemImage)
                .foregroundColor(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
            Text(category.rawValue)
        }
        .frame(maxWidth: .infinity)
        .font(.headline.weight(.bold))
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(VisualEffectBlur())
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.3 : 0.1), lineWidth: 0.5)
        )
    }
}

struct EmptyStateView: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles.square.filled.on.square").font(.system(size: 50)).foregroundColor(AppTheme.primaryTextColor(for: colorScheme)).opacity(0.8)
            VStack(spacing: 4) {
                Text("No Shortcuts Yet").font(.title3.weight(.bold))
                Text("Use the **+ Add Shortcut** button to begin.").font(.callout).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)).multilineTextAlignment(.center).lineSpacing(4)
            }
            Spacer()
        }.padding().frame(maxWidth: .infinity)
    }
}

struct AssignmentRow: View {
    @ObservedObject var manager: AppHotKeyManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    let assignment: Assignment
    var onShowEditOptions: () -> Void

    @Namespace private var pickerNamespace

    private var isConflicting: Bool { manager.conflictingAssignmentIDs.contains(assignment.id) }
    
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
            HStack(spacing: 12) {
                ShortcutIcon(target: assignment.configuration.target, manager: manager).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    ShortcutTitle(target: assignment.configuration.target)
                    ShortcutSubtitle(target: assignment.configuration.target)
                }
                Spacer()
                
                let shortcutString = manager.shortcutKeyCombinationString(for: assignment.shortcut)
                PillCard(content: {
                    HStack {
                        if assignment.trigger != .press {
                            Text(assignment.trigger.abbreviation)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                        }
                        Text(shortcutString)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                    }
                }, cornerRadius: AppTheme.cornerRadius)
                
                Button(action: onShowEditOptions) {
                    PillCard(content: {
                        Image(systemName: "pencil")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .frame(width: 18, height: 18, alignment: .center)
                            .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                    }, cornerRadius: AppTheme.cornerRadius)
                }.buttonStyle(.plain)

                Button(action: {
                    settings.currentProfile.wrappedValue.assignments.removeAll { $0.id == assignment.id }
                }) {
                    PillCard(content: {
                        Image(systemName: "trash.fill")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .frame(width: 18, height: 18, alignment: .center)
                            .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                    }, cornerRadius: AppTheme.cornerRadius)
                }.buttonStyle(.plain)
            }
            
            if isConflicting {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                    Text("Conflict detected. This hotkey & trigger combination is used multiple times.").font(.caption).fontWeight(.semibold).lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.vertical, 4).background(Color.yellow.opacity(0.2)).cornerRadius(AppTheme.cornerRadius)
            }
            
            if case .app = assignment.configuration.target {
                CustomSegmentedPicker(title: "Behavior Mode", selection: behaviorBinding, in: pickerNamespace, showKeyboardHints: false)
            }
        }
        .padding(12).background(BlurredBackgroundView()).clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous).stroke(isConflicting ? Color.yellow : Color.primary.opacity(colorScheme == .dark ? 0.3 : 0.1), lineWidth: isConflicting ? 1.5 : 0.5))
        .animation(.easeInOut, value: isConflicting)
    }
}

struct ShortcutRecordingView: View {
    @ObservedObject var manager: AppHotKeyManager
    @EnvironmentObject var settings: SettingsManager
    var isFloating: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var displayName: String {
        guard let state = manager.recordingState else { return "..." }
        switch state {
        case .create(let target), .edit(_, let target), .appAssigning(let target):
            return target.displayName
        case .cheatsheet:
            return "Cheatsheet"
        case .quickAssign:
            return "Quick Assign"
        }
    }

    private var showTriggerPicker: Bool {
        guard let state = manager.recordingState else { return false }
        switch state {
        case .cheatsheet:
            return false
        default:
            return true
        }
    }

    private var viewHeight: CGFloat {
        let baseHeight: CGFloat = isFloating ? 200.0 : 250.0
        return showTriggerPicker ? baseHeight + 50.0 : baseHeight
    }

    private var isRecordingForAppAssigning: Bool {
        if case .appAssigning = manager.recordingState {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(isRecordingForAppAssigning ? "Set Shortcut for \(displayName)" : "Recording for \(displayName)")
                    .font(.title2.weight(.bold))
                Text("Press a key combination to record it.")
                    .font(.callout)
            }
            .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))

            HStack(spacing: 10) {
                if manager.recordedKeys.isEmpty {
                    Text("Press any key...")
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                } else {
                    ForEach(manager.recordedKeys) { key in
                        Text(key.symbol)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme))
                            .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
                            .cornerRadius(AppTheme.cornerRadius)
                    }
                }
            }
            .frame(minHeight: 40)
            
            if showTriggerPicker {
                Picker("Trigger Type:", selection: $manager.recordedTriggerType) {
                    ForEach(ShortcutTriggerType.allCases) { trigger in
                        Text(trigger.rawValue).tag(trigger)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            }
            
            HStack(spacing: 15) {
                Button("Cancel") { manager.cancelRecording() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button(action: { manager.clearRecordedShortcut() }) {
                    Text("Blank")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .foregroundColor(AppTheme.adaptiveTextColor(on: AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme)))
                        .background(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme).opacity(0.8))
                        .cornerRadius(AppTheme.cornerRadius)
                }
                .buttonStyle(.plain)
                .opacity(isRecordingForAppAssigning ? 0 : 1)
                .disabled(isRecordingForAppAssigning)
                .keyboardShortcut("b", modifiers: [])

                Button(action: { manager.saveRecordedShortcut() }) {
                    Text("Done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .foregroundColor(AppTheme.adaptiveTextColor(on: AppTheme.accentColor2(for: colorScheme, theme: settings.appTheme)))
                        .background(AppTheme.accentColor2(for: colorScheme, theme: settings.appTheme))
                        .cornerRadius(AppTheme.cornerRadius)
                }
                .buttonStyle(.plain)
                .disabled(manager.recordedKeys.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 400, height: viewHeight)
        .background(VisualEffectBlur().clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)))
        .shadow(radius: 20)
    }
}

struct ShortcutIcon: View {
    let target: ShortcutTarget
    @ObservedObject var manager: AppHotKeyManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let icon = target.getIcon(using: manager, size: NSSize(width: 28, height: 28)) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 28))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius - 1, style: .continuous))
    }
}

struct ShortcutTitle: View {
    let target: ShortcutTarget
    var body: some View {
        Text(target.displayName).fontWeight(.semibold)
    }
}

struct ShortcutSubtitle: View {
    let target: ShortcutTarget
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let fullText = {
            switch target {
            case .app(_, let bundleId): return bundleId
            case .url(_, let address): return address
            case .file(_, let path): return path
            case .script(_, let command, _): return command
            case .shortcut(_, let executionName): return executionName
            case .snippet(_, let content): return content
            }
        }()
        
        HoverableTruncatedText(
            text: fullText,
            font: .caption,
            truncationMode: .middle,
            lineLimit: 1
        )
        .foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
    }
}

struct ListItemButtonStyle: ButtonStyle {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    
    var isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .fill(isHighlighted || configuration.isPressed ? AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme).opacity(0.3) : Color.clear)
                    .animation(.easeOut(duration: 0.1), value: isHighlighted)
            )
    }
}

struct AddAppView: View {
    var onSave: (String, String) -> Void
    @Binding var showingSheet: SheetType?
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var allApps: [AppInfo] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var highlightedAppID: AppInfo.ID?
    @FocusState private var isSearchFocused: Bool

    private var filteredApps: [AppInfo] {
        if searchText.isEmpty { return allApps }
        return allApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Add Application Shortcut")
                .font(.title2.weight(.bold))
                .padding(.top)
            
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                TextField("Search Applications...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let topApp = filteredApps.first {
                            onSave(topApp.name, topApp.id)
                        }
                    }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .padding(.horizontal)

            if isLoading {
                ProgressView().frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredApps) { app in
                                Button(action: { onSave(app.name, app.id) }) {
                                    HStack(spacing: 12) {
                                        Image(nsImage: app.icon)
                                            .resizable().aspectRatio(contentMode: .fit)
                                            .frame(width: 32, height: 32)
                                        VStack(alignment: .leading) {
                                            Text(app.name).fontWeight(.semibold)
                                            Text(app.id).font(.caption).foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)).truncationMode(.middle)
                                        }
                                        Spacer()
                                    }
                                    .padding(8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(ListItemButtonStyle(isHighlighted: highlightedAppID == app.id))
                                .id(app.id)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onChange(of: searchText) { _ in
                        highlightedAppID = filteredApps.first?.id
                    }
                    .onChange(of: highlightedAppID) { newID in
                        if let id = newID {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { showingSheet = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    if panel.runModal() == .OK, let url = panel.url, let bundleId = Bundle(url: url)?.bundleIdentifier {
                        var name = FileManager.default.displayName(atPath: url.path)
                        if name.hasSuffix(".app") {
                            name = String(name.dropLast(4))
                        }
                        onSave(name, bundleId)
                    }
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut("b", modifiers: [])
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 400, height: 550)
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isSearchFocused = true }
            if allApps.isEmpty {
                AppScanner.getAllApps { apps in
                    self.allApps = apps
                    self.isLoading = false
                    self.highlightedAppID = apps.first?.id
                }
            }
        }
        .onMoveCommand { direction in
            guard !filteredApps.isEmpty,
                  let currentId = highlightedAppID,
                  let currentIndex = filteredApps.firstIndex(where: { $0.id == currentId })
            else { return }

            var newIndex = currentIndex
            if direction == .up {
                newIndex = max(0, currentIndex - 1)
            } else if direction == .down {
                newIndex = min(filteredApps.count - 1, currentIndex + 1)
            }

            if newIndex != currentIndex {
                highlightedAppID = filteredApps[newIndex].id
            }
        }
        .onCommand(#selector(NSResponder.insertNewline(_:))) {
            guard let selectedId = highlightedAppID,
                  let app = filteredApps.first(where: { $0.id == selectedId })
            else { return }
            
            onSave(app.name, app.id)
        }
    }
}


struct AddURLView: View {
    var onSave: (String) -> Void
    @Binding var showingSheet: SheetType?
    @Environment(\.colorScheme) private var colorScheme
    @State private var urlString = "https://"
    @FocusState private var isURLFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Add URL Shortcut")
                .font(.title2.weight(.bold))

            URLTextField(text: $urlString)
                .focused($isURLFocused)
                .frame(height: 22)
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { showingSheet = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Next") { onSave(urlString) }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!isValidURL())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isURLFocused = true }
        }
    }

    private func isValidURL() -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}

struct AddScriptView: View {
    var onSave: (String, String, Bool) -> Void
    @Binding var showingSheet: SheetType?
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var scriptName = ""
    @State private var command = ""
    @State private var runsInTerminal = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Script Shortcut")
                .font(.title2.weight(.bold))
            
            TextField("Script Name (e.g., 'Toggle Wi-Fi')", text: $scriptName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $command)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                    .frame(height: 100)
                
                if command.isEmpty {
                    Text("echo 'Hello World'")
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }

            Toggle("Show in a new Terminal window", isOn: $runsInTerminal)
                .toggleStyle(.checkbox)
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { showingSheet = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Next") {
                    onSave(scriptName, command, runsInTerminal)
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(scriptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isNameFocused = true }
        }
    }
}

struct EditView: View {
    let assignment: Assignment
    @Binding var isPresented: Bool
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        switch assignment.configuration.target {
        case .app(let name, let bundleId):
            EditAppView(assignmentID: assignment.id, initialName: name, bundleId: bundleId, isPresented: $isPresented)
        case .url(let name, let address):
            EditURLView(assignmentID: assignment.id, initialName: name, initialURL: address, isPresented: $isPresented)
        case .file(let name, let path):
            EditFileView(assignmentID: assignment.id, initialName: name, initialPath: path, isPresented: $isPresented)
        case .script(let name, let command, let runsInTerminal):
            EditScriptView(assignmentID: assignment.id, initialName: name, initialCommand: command, initialRunsInTerminal: runsInTerminal, isPresented: $isPresented)
        case .shortcut(let name, let executionName):
            EditShortcutView(assignmentID: assignment.id, initialName: name, executionName: executionName, isPresented: $isPresented)
        case .snippet(let name, let content):
            EditSnippetView(assignmentID: assignment.id, initialName: name, initialContent: content, isPresented: $isPresented)
        }
    }
}

struct EditAppView: View {
    let assignmentID: UUID
    let bundleId: String
    @Binding var isPresented: Bool
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(assignmentID: UUID, initialName: String, bundleId: String, isPresented: Binding<Bool>) {
        self.assignmentID = assignmentID
        self.bundleId = bundleId
        self._isPresented = isPresented
        _name = State(initialValue: initialName)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit App Shortcut").font(.title2.weight(.bold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).focused($isFocused)
            Text(bundleId).font(.caption).foregroundColor(.secondary).truncationMode(.middle)
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { isPresented = false }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let newTarget = ShortcutTarget.app(name: name, bundleId: bundleId)
                    settings.updateAssignmentContent(id: assignmentID, newTarget: newTarget)
                    isPresented = false
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }.padding().frame(width: 400).foregroundColor(AppTheme.primaryTextColor(for: colorScheme)).onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
    }
}

struct EditURLView: View {
    let assignmentID: UUID
    @Binding var isPresented: Bool
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var name: String
    @State private var urlString: String
    @FocusState private var isFocused: Bool

    init(assignmentID: UUID, initialName: String, initialURL: String, isPresented: Binding<Bool>) {
        self.assignmentID = assignmentID
        self._isPresented = isPresented
        _name = State(initialValue: initialName)
        _urlString = State(initialValue: initialURL)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit URL Shortcut").font(.title2.weight(.bold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).focused($isFocused)
            URLTextField(text: $urlString).frame(height: 22)
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { isPresented = false }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let finalName = name.isEmpty ? (URL(string: urlString)?.host ?? "Link") : name
                    let newTarget = ShortcutTarget.url(name: finalName, address: urlString)
                    settings.updateAssignmentContent(id: assignmentID, newTarget: newTarget)
                    isPresented = false
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidURL())
            }
        }.padding().frame(width: 400).foregroundColor(AppTheme.primaryTextColor(for: colorScheme)).onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
    }

    private func isValidURL() -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}

struct EditFileView: View {
    let assignmentID: UUID
    @Binding var isPresented: Bool
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var name: String
    @State private var path: String
    @FocusState private var isFocused: Bool

    init(assignmentID: UUID, initialName: String, initialPath: String, isPresented: Binding<Bool>) {
        self.assignmentID = assignmentID
        self._isPresented = isPresented
        _name = State(initialValue: initialName)
        _path = State(initialValue: initialPath)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit File Shortcut").font(.title2.weight(.bold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).focused($isFocused)
            HStack {
                Text(path).font(.caption).foregroundColor(.secondary).truncationMode(.middle)
                Spacer()
                Button("Browse...") {
                    let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        self.path = url.path
                        if name.isEmpty {
                            self.name = url.lastPathComponent
                        }
                    }
                }
                .keyboardShortcut("b", modifiers: [])
            }
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { isPresented = false }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let newTarget = ShortcutTarget.file(name: name, path: path)
                    settings.updateAssignmentContent(id: assignmentID, newTarget: newTarget)
                    isPresented = false
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || path.isEmpty)
            }
        }.padding().frame(width: 400).foregroundColor(AppTheme.primaryTextColor(for: colorScheme)).onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
    }
}

struct EditScriptView: View {
    let assignmentID: UUID
    @Binding var isPresented: Bool
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var name: String
    @State private var command: String
    @State private var runsInTerminal: Bool
    @FocusState private var isFocused: Bool

    init(assignmentID: UUID, initialName: String, initialCommand: String, initialRunsInTerminal: Bool, isPresented: Binding<Bool>) {
        self.assignmentID = assignmentID
        self._isPresented = isPresented
        _name = State(initialValue: initialName)
        _command = State(initialValue: initialCommand)
        _runsInTerminal = State(initialValue: initialRunsInTerminal)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Script Shortcut").font(.title2.weight(.bold))
            TextField("Script Name", text: $name).textFieldStyle(.roundedBorder).focused($isFocused)
            TextEditor(text: $command)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                .frame(height: 100)
            Toggle("Show in a new Terminal window", isOn: $runsInTerminal)
                .toggleStyle(.checkbox)
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { isPresented = false }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let newTarget = ShortcutTarget.script(name: name, command: command, runsInTerminal: runsInTerminal)
                    settings.updateAssignmentContent(id: assignmentID, newTarget: newTarget)
                    isPresented = false
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || command.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
    }
}

struct EditShortcutView: View {
    let assignmentID: UUID
    let executionName: String
    @Binding var isPresented: Bool
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(assignmentID: UUID, initialName: String, executionName: String, isPresented: Binding<Bool>) {
        self.assignmentID = assignmentID
        self.executionName = executionName
        self._isPresented = isPresented
        _name = State(initialValue: initialName)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit macOS Shortcut").font(.title2.weight(.bold))
            TextField("Display Name", text: $name).textFieldStyle(.roundedBorder).focused($isFocused)
            Text("Executes: \(executionName)").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { isPresented = false }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let newTarget = ShortcutTarget.shortcut(name: name, executionName: executionName)
                    settings.updateAssignmentContent(id: assignmentID, newTarget: newTarget)
                    isPresented = false
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }.padding().frame(width: 400).foregroundColor(AppTheme.primaryTextColor(for: colorScheme)).onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
    }
}

struct ShortcutPickerView: View {
    var onSave: (String) -> Void
    @Binding var showingSheet: SheetType?
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var allShortcuts: [String] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var highlightedShortcut: String?
    @FocusState private var isSearchFocused: Bool

    private var filteredShortcuts: [String] {
        searchText.isEmpty ? allShortcuts : allShortcuts.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Select a macOS Shortcut")
                .font(.title2.weight(.bold))
                .padding(.top)
            
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                TextField("Search Shortcuts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let topShortcut = filteredShortcuts.first {
                            onSave(topShortcut)
                        }
                    }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .padding(.horizontal)

            if isLoading {
                ProgressView().frame(maxHeight: .infinity)
            } else if allShortcuts.isEmpty {
                Text("No Shortcuts Found").foregroundColor(AppTheme.secondaryTextColor(for: colorScheme)).frame(maxHeight: .infinity)
            } else {
                 ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredShortcuts, id: \.self) { shortcutName in
                                Button(action: { onSave(shortcutName) }) {
                                    HStack {
                                        Text(shortcutName)
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundColor(AppTheme.secondaryTextColor(for: colorScheme))
                                    }
                                    .padding(12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(ListItemButtonStyle(isHighlighted: highlightedShortcut == shortcutName))
                                .id(shortcutName)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onChange(of: searchText) { _ in
                        highlightedShortcut = filteredShortcuts.first
                    }
                    .onChange(of: highlightedShortcut) { newShortcut in
                        if let shortcut = newShortcut {
                            withAnimation {
                                proxy.scrollTo(shortcut, anchor: .center)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { showingSheet = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 400, height: 500)
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isSearchFocused = true }
            if allShortcuts.isEmpty {
                ShortcutRunner.getAllShortcutNames { names in
                    let sortedNames = names.sorted()
                    self.allShortcuts = sortedNames
                    self.isLoading = false
                    self.highlightedShortcut = sortedNames.first
                }
            }
        }
        .onMoveCommand { direction in
            guard !filteredShortcuts.isEmpty,
                  let currentShortcut = highlightedShortcut,
                  let currentIndex = filteredShortcuts.firstIndex(of: currentShortcut)
            else { return }

            var newIndex = currentIndex
            if direction == .up {
                newIndex = max(0, currentIndex - 1)
            } else if direction == .down {
                newIndex = min(filteredShortcuts.count - 1, currentIndex + 1)
            }

            if newIndex != currentIndex {
                highlightedShortcut = filteredShortcuts[newIndex]
            }
        }
        .onCommand(#selector(NSResponder.insertNewline(_:))) {
            if let shortcut = highlightedShortcut {
                onSave(shortcut)
            }
        }
    }
}

struct FooterView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var manager: AppHotKeyManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var isAddMenuPresented = false
    @State private var isShowingClearConfirmation = false
    var onShowHelp: () -> Void
    var onShowAppSettings: () -> Void
    var onAddFile: () -> Void
    @Binding var sheetType: SheetType?
    private let donationURL = URL(string: "https://www.patreon.com/MusaMatini")!

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: { isAddMenuPresented.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .foregroundColor(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                            .font(.system(size: 16, weight: .semibold))
                        Text("Add Shortcut")
                        KeyboardHint(key: "N")
                    }
                }
                .keyboardShortcut("n", modifiers: [])
                .popover(isPresented: $isAddMenuPresented, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Button(action: { sheetType = .addApp; isAddMenuPresented = false }) {
                             HStack { Text("Add App"); Spacer(); KeyboardHint(key: "1") }
                                .padding(6).contentShape(Rectangle())
                        }
                        .keyboardShortcut("1", modifiers: [])
                        
                        Button(action: { sheetType = .addShortcut; isAddMenuPresented = false }) {
                            HStack { Text("Add macOS Shortcut"); Spacer(); KeyboardHint(key: "2") }
                                .padding(6).contentShape(Rectangle())
                        }
                        .keyboardShortcut("2", modifiers: [])

                        Button(action: { sheetType = .addURL; isAddMenuPresented = false }) {
                             HStack { Text("Add URL"); Spacer(); KeyboardHint(key: "3") }
                                .padding(6).contentShape(Rectangle())
                        }
                        .keyboardShortcut("3", modifiers: [])

                        Button(action: { onAddFile(); isAddMenuPresented = false }) {
                             HStack { Text("Add File/Folder"); Spacer(); KeyboardHint(key: "4") }
                                .padding(6).contentShape(Rectangle())
                        }
                        .keyboardShortcut("4", modifiers: [])

                        Button(action: { sheetType = .addScript; isAddMenuPresented = false }) {
                             HStack { Text("Add Script"); Spacer(); KeyboardHint(key: "5") }
                                .padding(6).contentShape(Rectangle())
                        }
                        .keyboardShortcut("5", modifiers: [])

                        Button(action: { sheetType = .addSnippet; isAddMenuPresented = false }) {
                             HStack { Text("Add Snippet"); Spacer(); KeyboardHint(key: "6") }
                                .padding(6).contentShape(Rectangle())
                        }
                        .keyboardShortcut("6", modifiers: [])
                    }
                        
                    .padding(4)
                    .buttonStyle(.plain)
                    .frame(minWidth: 200)
                    .background { AppTheme.cardBackgroundColor(for: colorScheme, theme: settings.appTheme) }
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                }

                Spacer()
                Button(action: onShowAppSettings) {
                    HStack(spacing: 8) {
                        KeyboardHint(key: "S")
                        Text("App Settings")
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .keyboardShortcut("s", modifiers: [])
            }
            Divider().blendMode(.overlay)
            HStack {
                Button(action: onShowHelp) {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                            .font(.system(size: 16, weight: .semibold))
                        Text("How to Use")
                        KeyboardHint(key: "H")
                    }
                }
                .keyboardShortcut("h", modifiers: [])

                Spacer()
                
                Button(action: { openURL(donationURL) }) {
                    HStack(spacing: 8) {
                        KeyboardHint(key: "M")
                        Text("Support Me")
                        Image(systemName: "heart.circle.fill")
                            .foregroundColor(AppTheme.accentColor1(for: colorScheme, theme: settings.appTheme))
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .keyboardShortcut("m", modifiers: [])
            }
            Divider().blendMode(.overlay)
            HStack {
                Button(role: .destructive, action: { isShowingClearConfirmation = true }) {
                    HStack {
                        Text("Clear Profile")
                        KeyboardHint(key: "C")
                    }
                }
                .keyboardShortcut("c", modifiers: [])
                .disabled(settings.currentProfile.wrappedValue.assignments.isEmpty)
                
                Spacer()
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack {
                        KeyboardHint(key: "⌘Q")
                        Text("Quit WarpKey")
                    }
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .padding(16).background(ZStack { if colorScheme == .light { AppTheme.cardBackgroundColor(for: .light, theme: settings.appTheme) } else { VisualEffectBlur() } }.overlay(Color.black.opacity(colorScheme == .dark ? 0.1 : 0)))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)).overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous).stroke(Color.primary.opacity(colorScheme == .dark ? 0.3 : 0.1), lineWidth: 0.7))
        .padding(.horizontal, 10).padding(.bottom, 10).padding(.top, -134)
        .alert("Clear All Shortcuts in Profile?", isPresented: $isShowingClearConfirmation) {
            Button("Clear \"\(settings.currentProfile.wrappedValue.name)\"", role: .destructive) { settings.currentProfile.wrappedValue.assignments.removeAll() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This will remove all shortcuts from the currently selected profile. This cannot be undone.") }
    }
}

extension RecordingMode {
    var isFloating: Bool {
        if case .appAssigning = self {
            return true
        }
        return false
    }
}

struct AddSnippetView: View {
    var onSave: (String, String) -> Void
    @Binding var showingSheet: SheetType?
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var content = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Snippet Shortcut")
                .font(.title2.weight(.bold))
            
            TextField("Snippet Name (e.g., 'Email Signature')", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                    .frame(height: 150)
                
                if content.isEmpty {
                    Text("Enter your snippet content here...")
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { showingSheet = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Next") { onSave(name, content) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isNameFocused = true }
        }
    }
}

struct EditSnippetView: View {
    let assignmentID: UUID
    @Binding var isPresented: Bool
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var name: String
    @State private var content: String
    @FocusState private var isFocused: Bool

    init(assignmentID: UUID, initialName: String, initialContent: String, isPresented: Binding<Bool>) {
        self.assignmentID = assignmentID
        self._isPresented = isPresented
        _name = State(initialValue: initialName)
        _content = State(initialValue: initialContent)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Snippet").font(.title2.weight(.bold))
            TextField("Snippet Name", text: $name).textFieldStyle(.roundedBorder).focused($isFocused)
            
            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(AppTheme.pillBackgroundColor(for: colorScheme, theme: settings.appTheme).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                .frame(height: 150)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { isPresented = false }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let newTarget = ShortcutTarget.snippet(name: name, content: content)
                    settings.updateAssignmentContent(id: assignmentID, newTarget: newTarget)
                    isPresented = false
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || content.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .foregroundColor(AppTheme.primaryTextColor(for: colorScheme))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
    }
}

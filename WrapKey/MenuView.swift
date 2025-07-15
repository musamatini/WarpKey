import SwiftUI

enum AppPage { case welcome, settings, help }

struct MenuView: View {
    @ObservedObject var manager: AppHotKeyManager
    @ObservedObject var launchManager: LaunchAtLoginManager
    @EnvironmentObject var settings: SettingsManager
    
    @State private var currentPage: AppPage = .settings
    @State private var didAppear = false
    
    var body: some View {
        ZStack {
            if currentPage == .welcome {
                WelcomePage(onGetStarted: {
                    withAnimation(.easeIn(duration: 0.3)) {
                        currentPage = .settings
                    }
                })
                .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .move(edge: .leading))))
            } else {
                MainTabView(manager: manager, launchManager: launchManager)
                    .transition(.move(edge: .trailing))
            }
        }
        .onAppear {
            if !didAppear {
                if settings.hasCompletedOnboarding {
                    currentPage = .settings
                } else {
                    currentPage = .welcome
                }
                didAppear = true
            }
        }
        .frame(width: 450, height: 700)
        .foregroundColor(AppTheme.primaryTextColor)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        
    }
}

struct MainTabView: View {
    @ObservedObject var manager: AppHotKeyManager
    @ObservedObject var launchManager: LaunchAtLoginManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: AppPage = .settings
    
    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            ZStack {
                if selectedTab == .settings {
                    MainSettingsView(manager: manager, launchManager: launchManager, showHelpPage: { selectedTab = .help })
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .identity))
                }
                
                if selectedTab == .help {
                    HelpView(goBack: { selectedTab = .settings })
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
        .onDisappear {
            if settings.hasCompletedOnboarding {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goToHelpPageInMainWindow)) { _ in
            selectedTab = .help
        }
    }
}

// In your views file (e.g., MenuView.swift or a new file for components)

// Alternative Option: No background box

struct TitleBarButton: View {
    let systemName: String
    let action: () -> Void
    var tintColor: Color? // New parameter: Allows setting a specific tint color
    var yOffset: CGFloat = 0 // New parameter for vertical offset

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium)) // Slightly larger for better visibility
                .frame(width: 36, height: 36) // Larger frame to ensure a good tap target
                .contentShape(Rectangle()) // Makes the whole frame clickable
                // Use the provided tintColor, falling back to secondaryTextColor if not specified
                .foregroundColor(tintColor ?? AppTheme.secondaryTextColor)
        }
        .buttonStyle(.plain)
        .offset(y: yOffset) // Apply the offset here
    }
}

struct MenuBarIcon: View {
    var body: some View {
        Image("MenuBarIcon")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            // ✅ CHANGE: Use accentColor1 for the app's menu bar icon
            .foregroundColor(AppTheme.accentColor1)
            .frame(width: 18, height: 18) // Match icon size
             // Add padding to match the button's frame size for alignment
            .padding(9)
    }
}

// No other files need to be changed.
// Just replace the old versions of these two structs with the new ones.
struct CustomTitleBar: View {
    let title: String
    var showBackButton: Bool = false
    var onBack: (() -> Void)? = nil
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if showBackButton {
                TitleBarButton(systemName: "chevron.left", action: { onBack?() }, tintColor: AppTheme.accentColor1)
            } else {
                if let appIcon = NSImage(named: NSImage.Name("AppIcon")) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(4)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.accentColor1)
                        .frame(width: 28, height: 28)
                        .padding(4)
                }
            }

            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.primaryTextColor)

            Spacer()

            // MARK: Applied a negative yOffset to move the button up
            TitleBarButton(systemName: "xmark", action: onClose, tintColor: AppTheme.secondaryTextColor, yOffset: -2) // Nudge up by 1 point
        }
        .padding(.horizontal)
        .frame(height: 50)
    }
}

struct CustomSegmentedPicker<T: Hashable & CaseIterable & RawRepresentable>: View where T.RawValue == String {
    let title: String
    @Binding var selection: T
    private var namespace: Namespace.ID
    
    // Style constants for easier tweaking
    private let containerPadding: CGFloat = 4
    private let cornerRadius: CGFloat = AppTheme.cornerRadius

    init(title: String, selection: Binding<T>, in namespace: Namespace.ID) {
        self.title = title
        self._selection = selection
        self.namespace = namespace
    }
    
    var body: some View {
        HStack(spacing: 0) { // Use 0 spacing; padding on items will create the gap.
            ForEach(Array(T.allCases), id: \.self) { option in
                
                Text(option.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity) // Ensure each option's tap area is equal.
                    .foregroundColor(selection == option ? AppTheme.primaryTextColor : AppTheme.secondaryTextColor)
                    
                    // The magic happens here: the highlight is now a BACKGROUND modifier.
                    // This is a more stable pattern than a ZStack with sibling views.
                    .background(
                        ZStack {
                            if selection == option {
                                RoundedRectangle(cornerRadius: cornerRadius - containerPadding, style: .continuous)
                                    // ✅ CHANGE: Explicitly use accentColor1 for the selected background
                                    // It's highly likely AppTheme.pickerSelectedBackgroundColor
                                    // should be defined as AppTheme.accentColor1 in AppTheme.swift
                                    .fill(AppTheme.accentColor1)
                                    // The ID and namespace are what link the highlight's start and end positions.
                                    .matchedGeometryEffect(id: "picker-highlight", in: namespace)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // The animation block tells SwiftUI to animate the change.
                        // A slightly softer spring often feels better for this effect.
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.5)) {
                            selection = option
                        }
                    }
            }
        }
        .padding(containerPadding)
        .background(AppTheme.pickerBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct PillCard<Content: View>: View {
    let content: Content
    let backgroundColor: Color
    let cornerRadius: CGFloat

    init(@ViewBuilder content: () -> Content, backgroundColor: Color, cornerRadius: CGFloat) {
        self.content = content()
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
struct MainSettingsView: View {
    @ObservedObject var manager: AppHotKeyManager
    @ObservedObject var launchManager: LaunchAtLoginManager
    @Environment(\.dismiss) private var dismiss
    var showHelpPage: () -> Void

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // Title bar stays at the top
                CustomTitleBar(title: "WarpKey Settings", onClose: { dismiss() })

                // Main content changes based on assignment state
                if manager.assignments.isEmpty {
                    EmptyStateView()
                        .frame(maxHeight: .infinity) // Fill space to avoid footer push
                } else {
                    AssignmentListView(
                        manager: manager,
                        launchManager: launchManager,
                        showHelpPage: showHelpPage
                    )
                    // Ensures 10px margin under the scrollable list
                    .padding(.bottom, 1)
                }
            }
            .frame(maxHeight: .infinity)

            // Always show the footer at the bottom
            .safeAreaInset(edge: .bottom) {
                FooterView(
                    manager: manager,
                    launchManager: launchManager,
                    isClearButtonDisabled: manager.assignments.isEmpty,
                    onShowHelp: showHelpPage
                )
                .padding(.horizontal, 0) // <- adds "margin" from screen edge
            }

        }
    }
}
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles.square.filled.on.square")
                .font(.system(size: 50))
                .symbolRenderingMode(.palette)
                // ✅ FIX: Main icon color is now accentColor1
                .foregroundStyle(AppTheme.accentColor1)
            VStack(spacing: 4) {
                Text("No Shortcuts Yet").font(.title3.weight(.bold))
                Text("Assign your first app with\n**R-Opt + R-Cmd + Letter**").font(.callout).foregroundColor(AppTheme.secondaryTextColor).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
struct AssignmentListView: View {
    @ObservedObject var manager: AppHotKeyManager
    @ObservedObject var launchManager: LaunchAtLoginManager
    var showHelpPage: () -> Void
    
    // Adjustable padding value — you can make this a @State if needed
    let bottomSpacing: CGFloat = 133 // <- you can adjust this

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 18) {
                ForEach(manager.assignments.sorted(by: { $0.key < $1.key }), id: \.key) { keyCode, config in
                    AssignmentRow(manager: manager, keyCode: keyCode, configuration: config)
                        .id(keyCode)
                        .animation(.easeInOut(duration: 0.3), value: config.behavior)
                }

                // Add extra space under the last app
                Spacer()
                    .frame(height: bottomSpacing)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
        .frame(maxHeight: .infinity)
    }
}



struct AssignmentRow: View {
    @ObservedObject var manager: AppHotKeyManager
    let keyCode: CGKeyCode
    let configuration: ShortcutConfiguration
    @Namespace private var pickerNamespace

    private var behaviorBinding: Binding<ShortcutConfiguration.Behavior> {
        Binding(get: { self.configuration.behavior }, set: { newBehavior in manager.updateBehavior(for: keyCode, to: newBehavior) })
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 15) {
                if let icon = manager.getAppIcon(for: configuration.bundleId) {
                    Image(nsImage: icon).resizable().frame(width: 36, height: 36)
                } else {
                    Image(systemName: "app.dashed").font(.system(size: 28)).frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.getAppName(for: configuration.bundleId) ?? "Unknown App").fontWeight(.semibold)
                    Text(configuration.bundleId).font(.caption).foregroundColor(AppTheme.secondaryTextColor).truncationMode(.middle)
                }
                Spacer()

                PillCard(content: {
                    Text("⌘ + \(manager.keyString(for: keyCode))")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                }, backgroundColor: AppTheme.pillBackgroundColor, cornerRadius: AppTheme.cornerRadius)
                
                Button(action: { manager.removeAssignment(keyCode: keyCode) }) {
                    PillCard(content: {
                        Image(systemName: "trash.fill")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundColor(AppTheme.secondaryTextColor) // Kept as secondary for destructive action
                    }, backgroundColor: AppTheme.pillBackgroundColor, cornerRadius: AppTheme.cornerRadius)
                }
                .buttonStyle(.plain)
            }
            // Note: If CustomSegmentedPicker has its own accent color,
            // ensure it's configured to use AppTheme.accentColor1 internally.
            CustomSegmentedPicker(title: "Behavior Mode", selection: behaviorBinding, in: pickerNamespace)
        }
        .padding(12)
        .background(BlurredBackgroundView())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                        .stroke(AppTheme.primaryTextColor.opacity(0.3), lineWidth: 0.5)
                )
        .padding(.horizontal, 8)
    }
}


struct FooterView: View {
    @ObservedObject var manager: AppHotKeyManager
    @ObservedObject var launchManager: LaunchAtLoginManager
    @EnvironmentObject var settings: SettingsManager
    @State private var isShowingClearConfirmation = false
    var isClearButtonDisabled: Bool
    var onShowHelp: () -> Void
    private let donationURL = URL(string: "https://www.buymeocoffee.com/musamatini")!

    private let showDebugWelcomeButton = true

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                // Group 1: Show Menu Bar Icon with its checkbox
                HStack(spacing: 4) { // Add a small space between toggle and text
                    Toggle(isOn: $settings.showMenuBarIcon) {
                        EmptyView() // Hide the default label part of the toggle
                    }
                    .labelsHidden() // Ensure no label is displayed by the Toggle itself
                    .tint(AppTheme.accentColor1) // Apply tint to the checkbox
                    
                    Text("Show Menu Bar Icon")
                        .foregroundColor(AppTheme.primaryTextColor)
                }
                
                Spacer() // This Spacer pushes the second group to the right
                
                // Group 2: Launch at Login with its checkbox (checkbox on the right)
                HStack(spacing: 4) { // Add a small space between text and toggle
                    Text("Launch at Login")
                        .foregroundColor(AppTheme.primaryTextColor)
                    
                    Toggle(isOn: $launchManager.isEnabled) {
                        EmptyView() // Hide the default label part of the toggle
                    }
                    .labelsHidden() // Ensure no label is displayed by the Toggle itself
                    .tint(AppTheme.accentColor1) // Apply tint to the checkbox
                }
            }

            Divider().blendMode(.overlay)
            
            HStack {
                Button(action: onShowHelp) {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(AppTheme.accentColor1, AppTheme.primaryTextColor)
                            .font(.system(size: 16))
                            .offset(y: -0.2) // Adjust this offset for vertical centering
                        Text("How to Use")
                            .foregroundColor(AppTheme.primaryTextColor)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Link(destination: donationURL) {
                    HStack(spacing: 8) {
                        Text("Support Me")
                            .foregroundColor(AppTheme.primaryTextColor)
                        Image(systemName: "heart.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(AppTheme.accentColor1, AppTheme.primaryTextColor)
                            .font(.system(size: 16))
                            .offset(y: -0.2) // Adjust this offset for vertical centering
                    }
                }
                .buttonStyle(.plain)
            }
            
            Divider().blendMode(.overlay)
            
            HStack {
                Button("Clear All", role: .destructive) { isShowingClearConfirmation = true }.disabled(isClearButtonDisabled)
                Spacer()
                Button("Quit WarpKey") { NSApplication.shared.terminate(nil) }
            }
            .foregroundColor(AppTheme.secondaryTextColor)
            
            if showDebugWelcomeButton {
                #if DEBUG
                Divider().blendMode(.overlay)
                Button(action: {
                    print("[DEBUG] Resetting onboarding state.")
                    settings.hasCompletedOnboarding = false
                }) {
                    Label("DEBUG: Show Welcome Screen Again", systemImage: "arrow.uturn.backward.circle.fill")
                        .foregroundColor(.yellow)
                }
                .padding(.top, 5)
                #endif
            }
        }
        .font(.body)
        .buttonStyle(.plain)
        .padding(16)
        .background(VisualEffectBlur()
            .overlay(Color.black.opacity(0.1)))
        
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                        .stroke(AppTheme.primaryTextColor.opacity(0.3), lineWidth: 0.7)
                )
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, -134)
        .alert("Clear All Shortcuts?", isPresented: $isShowingClearConfirmation) {
            Button("Clear All", role: .destructive) {
                manager.clearAllAssignments()
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This action cannot be undone. All your assigned shortcuts will be permanently removed.") }
    }
}
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .popover
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct BlurredBackgroundView: View {
    var body: some View {
        VisualEffectBlur()
            .overlay(Color.white.opacity(0.01))
    }
}

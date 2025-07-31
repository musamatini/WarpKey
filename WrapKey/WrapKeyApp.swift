//WrapKeyApp.swift
import SwiftUI
import AppKit
import Sparkle
import Combine

// MARK: - Updater View Model
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates: Bool

    private let updater: SPUUpdater
    private var cancellables = Set<AnyCancellable>()

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates

        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        
        $automaticallyChecksForUpdates
            .dropFirst()
            .sink { [weak self] checksAutomatically in
                self?.updater.automaticallyChecksForUpdates = checksAutomatically
            }
            .store(in: &cancellables)
    }
    
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

// MARK: - Menu Item View
struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel
    
    var body: some View {
        Button("Check for Updates…") {
            updaterViewModel.checkForUpdates()
        }
        .disabled(!updaterViewModel.canCheckForUpdates)
    }
}

// MARK: - Helper View for Environment-based Injection
struct AppDelegateInjector: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear {
                appDelegate.openWindowAction = openWindow
            }
    }
}


// MARK: - Main App
@main
struct WrapKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var settingsManager: SettingsManager
    @StateObject private var hotKeyManager: AppHotKeyManager
    @StateObject private var launchManager = LaunchAtLoginManager()

    init() {
        let settings = SettingsManager()
        let hotKey = AppHotKeyManager(settings: settings)
        
        _settingsManager = StateObject(wrappedValue: settings)
        _hotKeyManager = StateObject(wrappedValue: hotKey)
        
        appDelegate.settings = settings
        appDelegate.hotKeyManager = hotKey
    }

    private var preferredColorScheme: ColorScheme? {
        switch settingsManager.colorScheme {
        case .light: return .light
        case .dark: return .dark
        case .auto: return settingsManager.systemColorScheme
        }
    }
    
    var body: some Scene {
        Window("WrapKey", id: "main-menu") {
            MenuView(
                manager: hotKeyManager,
                launchManager: launchManager,
                updaterViewModel: appDelegate.updaterViewModel
            )
            .environmentObject(settingsManager)
            .background(WindowAccessor())
            .preferredColorScheme(preferredColorScheme)
            .background(AppDelegateInjector(appDelegate: appDelegate))
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: appDelegate.updaterViewModel)
            }
            CommandGroup(replacing: .windowList) {}
        }
    }
}

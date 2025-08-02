// WrapKeyApp.swift
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



// MARK: - Root View to Manage Color Scheme
struct RootView: View {
    @ObservedObject var settings: SettingsManager
    let appDelegate: AppDelegate
    @StateObject private var launchManager = LaunchAtLoginManager()

    private var preferredColorScheme: ColorScheme? {
        switch settings.colorScheme {
        case .light: return .light
        case .dark: return .dark
        case .auto: return settings.systemColorScheme
        }
    }

    var body: some View {
        MenuView(
            manager: appDelegate.hotKeyManager,
            launchManager: launchManager,
            updaterViewModel: appDelegate.updaterViewModel
        )
        .environmentObject(settings)
        .preferredColorScheme(preferredColorScheme)
    }
}


// MARK: - Main App
@main
struct WrapKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {

        Settings {
            EmptyView()
        }
    }
}

// WarpKeyApp.swift

import SwiftUI
import AppKit
import Sparkle
import Combine

// MARK: - Updater View Model (The Bridge)

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

// MARK: - Main App

@main
struct WarpKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var launchManager = LaunchAtLoginManager()
    @StateObject private var updaterViewModel: UpdaterViewModel

    @Environment(\.openWindow) var openWindow
    
    init() {
        let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        _updaterViewModel = StateObject(wrappedValue: UpdaterViewModel(updater: updater.updater))
        
        let appDelegate = NSApplication.shared.delegate as? AppDelegate
        appDelegate?.updaterController = updater
    }

    var body: some Scene {
        let settings = appDelegate.settings
        let hotKeyManager = appDelegate.hotKeyManager
        let _ = { appDelegate.openWindowAction = openWindow }()

        Window("WarpKey", id: "main-menu") {
            MenuView(
                manager: hotKeyManager,
                launchManager: launchManager,
                updaterViewModel: updaterViewModel
            )
            .environmentObject(settings)
            .background(WindowAccessor())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
            CommandGroup(replacing: .windowList) {}
        }
    }
}

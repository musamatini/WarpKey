//LaunchAtLoginManager.swift
import Foundation
import ServiceManagement
import Combine

// MARK: - Launch At Login Manager
class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool = SMAppService.mainApp.status == .enabled
    private var cancellable: AnyCancellable?
    
    init() {
        cancellable = $isEnabled.sink { [weak self] desiredState in
            guard let self = self else { return }
            let currentState = (SMAppService.mainApp.status == .enabled)
            if desiredState != currentState {
                self.toggle(enabled: desiredState)
            }
        }
    }

    private func toggle(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .notFound {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[LaunchAtLogin] Error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

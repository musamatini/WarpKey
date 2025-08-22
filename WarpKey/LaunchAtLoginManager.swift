//LaunchAtLogin.swift
import Foundation
import ServiceManagement
import Combine

class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool = SMAppService.mainApp.status == .enabled
    private var cancellable: AnyCancellable?
    
    init() {
        cancellable = $isEnabled
            .removeDuplicates()
            .sink { [weak self] desiredState in
                guard let self = self else { return }
                
                self.toggle(enabled: desiredState)
        }
    }

    private func toggle(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            DispatchQueue.main.async {
                 self.isEnabled = SMAppService.mainApp.status == .enabled
            }
        } catch {
            print("[LaunchAtLogin] Error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

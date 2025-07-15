// LaunchAtLoginManager.swift

import Foundation
import ServiceManagement
import Combine

// An ObservableObject to manage the launch-at-login state.
class LaunchAtLoginManager: ObservableObject {
    
    // @Published property will update the UI automatically.
    @Published var isEnabled: Bool = SMAppService.mainApp.status == .enabled

    // A cancellable object to store the subscription.
    private var cancellable: AnyCancellable?
    
    init() {
        // Observe changes to the isEnabled property.
        cancellable = $isEnabled.sink { [weak self] desiredState in
            guard let self = self else { return }

            // Get the actual current state of the service.
            let currentState = (SMAppService.mainApp.status == .enabled)

            // Only call the toggle function if the desired state is
            // different from the actual current state. This breaks the loop.
            if desiredState != currentState {
                self.toggle(enabled: desiredState)
            }
        }
    }

    // This function does the actual work of enabling or disabling the service.
    private func toggle(enabled: Bool) {
        do {
            if enabled {
                // Register the app to launch at login.
                if SMAppService.mainApp.status == .notFound {
                    try SMAppService.mainApp.register()
                    print("[LaunchAtLogin] Successfully registered.")
                }
            } else {
                // Unregister the app.
                try SMAppService.mainApp.unregister()
                print("[LaunchAtLogin] Successfully unregistered.")
            }
        } catch {
            // If something goes wrong, print the error and reset the toggle.
            print("[LaunchAtLogin] Error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

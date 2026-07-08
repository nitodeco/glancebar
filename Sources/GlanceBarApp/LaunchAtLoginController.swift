import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    func apply(isEnabled: Bool) {
        guard #available(macOS 13.0, *) else {
            return
        }

        do {
            if isEnabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }

            if !isEnabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Failed to update launch at login: \(error.localizedDescription)")
        }
    }
}

import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    @discardableResult
    func apply(isEnabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else {
            return true
        }

        do {
            if isEnabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }

            if !isEnabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }

            return true
        } catch {
            NSLog("Failed to update launch at login: \(error.localizedDescription)")
            return false
        }
    }
}

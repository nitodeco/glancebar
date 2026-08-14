import AppKit

private let deleteSettingsCheckboxTitle = "Delete my settings too"

struct UninstallService {
    let moveToTrash: (URL) throws -> Void
    let setLaunchAtLoginEnabled: (Bool) -> Bool
    let deleteSettings: () -> Void

    func uninstall(
        applicationURL: URL,
        isLaunchAtLoginEnabled: Bool,
        isSettingsDeletionRequested: Bool
    ) throws {
        guard applicationURL.pathExtension == "app" else {
            throw UninstallError.applicationBundleNotFound
        }

        guard setLaunchAtLoginEnabled(false) else {
            throw UninstallError.launchAtLoginCouldNotBeDisabled
        }

        do {
            try moveToTrash(applicationURL)
        } catch {
            if isLaunchAtLoginEnabled {
                _ = setLaunchAtLoginEnabled(true)
            }

            throw error
        }

        if isSettingsDeletionRequested {
            deleteSettings()
        }
    }
}

enum UninstallError: LocalizedError, Equatable {
    case applicationBundleNotFound
    case launchAtLoginCouldNotBeDisabled

    var errorDescription: String? {
        if case .applicationBundleNotFound = self {
            return "GlanceBar is not running from an installed application bundle."
        }

        return "GlanceBar could not disable Launch at Login."
    }
}

@MainActor
final class UninstallCoordinator {
    private let service: UninstallService

    init(launchAtLoginController: LaunchAtLoginController) {
        service = UninstallService(
            moveToTrash: { applicationURL in
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: applicationURL, resultingItemURL: &resultingURL)
            },
            setLaunchAtLoginEnabled: { isEnabled in
                launchAtLoginController.apply(isEnabled: isEnabled)
            },
            deleteSettings: {
                guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
                    return
                }

                UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            }
        )
    }

    func confirmAndUninstall(isLaunchAtLoginEnabled: Bool, window: NSWindow?) {
        let deleteSettingsCheckbox = NSButton(
            checkboxWithTitle: deleteSettingsCheckboxTitle,
            target: nil,
            action: nil
        )
        let alert = NSAlert()
        alert.messageText = "Uninstall GlanceBar?"
        alert.informativeText = "GlanceBar will be moved to Trash and removed from Launch at Login."
        alert.alertStyle = .warning
        alert.accessoryView = deleteSettingsCheckbox
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else {
                return
            }

            self?.uninstall(
                isLaunchAtLoginEnabled: isLaunchAtLoginEnabled,
                isSettingsDeletionRequested: deleteSettingsCheckbox.state == .on,
                window: window
            )
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func uninstall(
        isLaunchAtLoginEnabled: Bool,
        isSettingsDeletionRequested: Bool,
        window: NSWindow?
    ) {
        do {
            try service.uninstall(
                applicationURL: Bundle.main.bundleURL,
                isLaunchAtLoginEnabled: isLaunchAtLoginEnabled,
                isSettingsDeletionRequested: isSettingsDeletionRequested
            )
            NSApp.terminate(nil)
        } catch {
            let errorAlert = NSAlert(error: error)

            if let window {
                errorAlert.beginSheetModal(for: window)
            } else {
                errorAlert.runModal()
            }
        }
    }
}

import Foundation
import Testing
@testable import GlanceBarApp

private enum TestUninstallError: Error, Equatable {
    case moveFailed
}

@Test func uninstallsAndDeletesSettingsWhenRequested() throws {
    var trashedURLs: [URL] = []
    var launchAtLoginStates: [Bool] = []
    var settingsDeletionCount = 0
    let service = UninstallService(
        moveToTrash: { applicationURL in
            trashedURLs.append(applicationURL)
        },
        setLaunchAtLoginEnabled: { isEnabled in
            launchAtLoginStates.append(isEnabled)
            return true
        },
        deleteSettings: {
            settingsDeletionCount += 1
        }
    )
    let applicationURL = URL(fileURLWithPath: "/Applications/GlanceBar.app")

    try service.uninstall(
        applicationURL: applicationURL,
        isLaunchAtLoginEnabled: true,
        isSettingsDeletionRequested: true
    )

    #expect(trashedURLs == [applicationURL])
    #expect(launchAtLoginStates == [false])
    #expect(settingsDeletionCount == 1)
}

@Test func restoresLaunchAtLoginAndPreservesSettingsWhenTrashFails() {
    var launchAtLoginStates: [Bool] = []
    var settingsDeletionCount = 0
    let service = UninstallService(
        moveToTrash: { _ in
            throw TestUninstallError.moveFailed
        },
        setLaunchAtLoginEnabled: { isEnabled in
            launchAtLoginStates.append(isEnabled)
            return true
        },
        deleteSettings: {
            settingsDeletionCount += 1
        }
    )

    #expect(throws: TestUninstallError.moveFailed) {
        try service.uninstall(
            applicationURL: URL(fileURLWithPath: "/Applications/GlanceBar.app"),
            isLaunchAtLoginEnabled: true,
            isSettingsDeletionRequested: true
        )
    }
    #expect(launchAtLoginStates == [false, true])
    #expect(settingsDeletionCount == 0)
}

@Test func rejectsNonApplicationBundle() {
    let service = UninstallService(
        moveToTrash: { _ in },
        setLaunchAtLoginEnabled: { _ in true },
        deleteSettings: {}
    )

    #expect(throws: UninstallError.applicationBundleNotFound) {
        try service.uninstall(
            applicationURL: URL(fileURLWithPath: "/tmp/GlanceBar"),
            isLaunchAtLoginEnabled: true,
            isSettingsDeletionRequested: false
        )
    }
}

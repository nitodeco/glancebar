import Testing
@testable import GlanceBarApp

@MainActor
private final class UpdaterDriverSpy: UpdaterDriving {
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = true
    private(set) var startCount = 0
    private(set) var backgroundCheckCount = 0
    private(set) var manualCheckCount = 0
    private(set) var resetUpdateCycleCount = 0

    func start() {
        startCount += 1
    }

    func checkForUpdatesInBackground() {
        backgroundCheckCount += 1
    }

    func checkForUpdates() {
        manualCheckCount += 1
    }

    func resetUpdateCycleAfterShortDelay() {
        resetUpdateCycleCount += 1
    }
}

@Test func formatsUpdateMenuTitleFromAvailability() {
    #expect(getUpdateMenuTitle(availability: .available) == "Update available")
    #expect(getUpdateMenuTitle(availability: .notAvailable) == "Check for updates")
}

@MainActor
@Test func startsImmediateBackgroundChecksAndPersistsAutomaticDownloads() {
    let updaterDriver = UpdaterDriverSpy()
    var stateChangeCount = 0
    let updaterCoordinator = UpdaterCoordinator(updaterDriver: updaterDriver) {
        stateChangeCount += 1
    }

    updaterCoordinator.start()
    updaterCoordinator.setAutoUpdateEnabled(false)
    updaterCoordinator.checkForUpdates()

    #expect(updaterDriver.startCount == 1)
    #expect(updaterDriver.automaticallyChecksForUpdates)
    #expect(updaterDriver.backgroundCheckCount == 1)
    #expect(!updaterDriver.automaticallyDownloadsUpdates)
    #expect(updaterDriver.resetUpdateCycleCount == 1)
    #expect(updaterDriver.manualCheckCount == 1)
    #expect(stateChangeCount == 1)
}

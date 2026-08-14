import Sparkle

enum UpdateAvailability: Equatable {
    case available
    case notAvailable
}

func getUpdateMenuTitle(availability: UpdateAvailability) -> String {
    availability == .available ? "Update available" : "Check for updates"
}

@MainActor
protocol UpdaterDriving: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }

    func start()
    func checkForUpdatesInBackground()
    func checkForUpdates()
    func resetUpdateCycleAfterShortDelay()
}

@MainActor
private final class SparkleUpdaterDriver: UpdaterDriving {
    private let updaterController: SPUStandardUpdaterController

    init(updaterDelegate: SPUUpdaterDelegate) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            updaterController.updater.automaticallyChecksForUpdates
        }
        set {
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get {
            updaterController.updater.automaticallyDownloadsUpdates
        }
        set {
            updaterController.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func start() {
        updaterController.startUpdater()
    }

    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func resetUpdateCycleAfterShortDelay() {
        updaterController.updater.resetUpdateCycleAfterShortDelay()
    }
}

@MainActor
final class UpdaterCoordinator: NSObject, SPUUpdaterDelegate {
    private let providedUpdaterDriver: UpdaterDriving?
    private let onStateChange: () -> Void
    private lazy var updaterDriver = providedUpdaterDriver ?? SparkleUpdaterDriver(updaterDelegate: self)
    private(set) var availability = UpdateAvailability.notAvailable

    init(updaterDriver: UpdaterDriving? = nil, onStateChange: @escaping () -> Void) {
        providedUpdaterDriver = updaterDriver
        self.onStateChange = onStateChange
        super.init()
    }

    var isAutoUpdateEnabled: Bool {
        updaterDriver.automaticallyDownloadsUpdates
    }

    func start() {
        updaterDriver.start()
        updaterDriver.automaticallyChecksForUpdates = true
        updaterDriver.checkForUpdatesInBackground()
    }

    func setAutoUpdateEnabled(_ isEnabled: Bool) {
        updaterDriver.automaticallyDownloadsUpdates = isEnabled
        updaterDriver.resetUpdateCycleAfterShortDelay()
        onStateChange()
    }

    func checkForUpdates() {
        updaterDriver.checkForUpdates()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availability = .available
        onStateChange()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availability = .notAvailable
        onStateChange()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        availability = .notAvailable
        NSLog("Update check failed: %@", error.localizedDescription)
        onStateChange()
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        guard updater.automaticallyDownloadsUpdates else {
            return false
        }

        DispatchQueue.main.async {
            immediateInstallHandler()
        }

        return true
    }
}

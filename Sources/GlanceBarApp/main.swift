import AppKit
import GlanceBarCore

private let metricsTimerToleranceInSeconds: TimeInterval = 0.5

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: StatusMetricsView.preferredSize.width)
    private let metricsReader = SystemMetricsReader()
    private let metricsView = StatusMetricsView(frame: NSRect(origin: .zero, size: StatusMetricsView.preferredSize))
    private let configurationStore: AppConfigurationStore
    private var configuration: AppConfiguration
    private var timer: Timer?

    override init() {
        let configurationStore = AppConfigurationStore()
        self.configurationStore = configurationStore
        configuration = configurationStore.load()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        metricsView.configuration = configuration
        configureStatusButton()
        statusItem.menu = makeMenu()
        updateMetrics()
        scheduleTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    @objc private func updateMetrics() {
        metricsView.snapshot = metricsReader.readSnapshot()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: configuration.pollingIntervalInSeconds,
            target: self,
            selector: #selector(updateMetrics),
            userInfo: nil,
            repeats: true
        )
        timer?.tolerance = metricsTimerToleranceInSeconds
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        metricsView.autoresizingMask = [.width, .height]
        metricsView.frame = button.bounds
        button.addSubview(metricsView)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settingsItem = NSMenuItem()
        settingsItem.view = SettingsMenuView(configuration: configuration) { [weak self] configuration in
            self?.apply(configuration: configuration)
        }
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    private func apply(configuration newConfiguration: AppConfiguration) {
        let previousPollingIntervalInSeconds = configuration.pollingIntervalInSeconds
        configuration = newConfiguration
        configurationStore.save(newConfiguration)
        metricsView.configuration = newConfiguration

        if previousPollingIntervalInSeconds != newConfiguration.pollingIntervalInSeconds {
            scheduleTimer()
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

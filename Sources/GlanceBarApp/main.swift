import AppKit
import GlanceBarCore

private let metricsTimerToleranceInSeconds: TimeInterval = 0.5

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let metricsReader = SystemMetricsReader()
    private let metricsView = StatusMetricsView(frame: .zero)
    private let configurationStore: AppConfigurationStore
    private var configuration: AppConfiguration
    private var maybeLatestSnapshot: MetricsSnapshot?
    private var maybeGpuUsagePercent: Int?
    private var timer: Timer?
    private var gpuTimer: Timer?
    private var settingsWindowController: SettingsWindowController?

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
        scheduleGpuTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        gpuTimer?.invalidate()
    }

    @objc private func updateMetrics() {
        let snapshot = metricsReader.readSnapshot()
        maybeLatestSnapshot = MetricsSnapshot(
            cpuUsagePercent: snapshot.cpuUsagePercent,
            gpuUsagePercent: configuration.isGpuEnabled ? maybeGpuUsagePercent : nil,
            ramUsagePercent: snapshot.ramUsagePercent,
            ssdUsagePercent: snapshot.ssdUsagePercent,
            networkUploadBytesPerSecond: snapshot.networkUploadBytesPerSecond,
            networkDownloadBytesPerSecond: snapshot.networkDownloadBytesPerSecond
        )
        syncMetricsViewSnapshot()
    }

    @objc private func updateGpuMetrics() {
        maybeGpuUsagePercent = metricsReader.readGpuUsagePercent()
        syncMetricsViewSnapshot()
    }

    private func syncMetricsViewSnapshot() {
        guard let maybeLatestSnapshot else {
            return
        }

        metricsView.snapshot = MetricsSnapshot(
            cpuUsagePercent: maybeLatestSnapshot.cpuUsagePercent,
            gpuUsagePercent: configuration.isGpuEnabled ? maybeGpuUsagePercent : nil,
            ramUsagePercent: maybeLatestSnapshot.ramUsagePercent,
            ssdUsagePercent: maybeLatestSnapshot.ssdUsagePercent,
            networkUploadBytesPerSecond: maybeLatestSnapshot.networkUploadBytesPerSecond,
            networkDownloadBytesPerSecond: maybeLatestSnapshot.networkDownloadBytesPerSecond
        )
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

    private func scheduleGpuTimer() {
        gpuTimer?.invalidate()
        maybeGpuUsagePercent = nil

        guard configuration.isGpuEnabled else {
            syncMetricsViewSnapshot()
            return
        }

        updateGpuMetrics()
        gpuTimer = Timer.scheduledTimer(
            timeInterval: configuration.gpuPollingIntervalInSeconds,
            target: self,
            selector: #selector(updateGpuMetrics),
            userInfo: nil,
            repeats: true
        )
        gpuTimer?.tolerance = metricsTimerToleranceInSeconds
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        updateStatusItemSize()
        button.addSubview(metricsView)
    }

    private func updateStatusItemSize() {
        let preferredSize = StatusMetricsView.preferredSize(configuration: configuration)
        statusItem.length = preferredSize.width
        metricsView.frame = NSRect(origin: .zero, size: preferredSize)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc private func showSettings() {
        let settingsWindowController = settingsWindowController ?? SettingsWindowController(configuration: configuration) { [weak self] configuration in
            self?.apply(configuration: configuration)
        }
        self.settingsWindowController = settingsWindowController
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func apply(configuration newConfiguration: AppConfiguration) {
        let previousPollingIntervalInSeconds = configuration.pollingIntervalInSeconds
        let previousIsGpuEnabled = configuration.isGpuEnabled
        let previousGpuPollingIntervalInSeconds = configuration.gpuPollingIntervalInSeconds
        configuration = newConfiguration
        configurationStore.save(newConfiguration)
        metricsView.configuration = newConfiguration
        updateStatusItemSize()
        syncMetricsViewSnapshot()

        if previousPollingIntervalInSeconds != newConfiguration.pollingIntervalInSeconds {
            scheduleTimer()
        }

        if previousIsGpuEnabled != newConfiguration.isGpuEnabled || previousGpuPollingIntervalInSeconds != newConfiguration.gpuPollingIntervalInSeconds {
            scheduleGpuTimer()
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

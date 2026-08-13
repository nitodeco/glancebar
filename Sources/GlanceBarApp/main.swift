import AppKit
import GlanceBarCore

private let metricsTimerToleranceInSeconds: TimeInterval = 0.5

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let metricsPollingWorker = MetricsPollingWorker()
    private let metricsView = StatusMetricsView(frame: .zero)
    private let configurationStore: AppConfigurationStore
    private let adaptiveTextContrastSampler = AdaptiveTextContrastSampler()
    private let launchAtLoginController = LaunchAtLoginController()
    private var configuration: AppConfiguration
    private var maybeLatestSnapshot: MetricsSnapshot?
    private var maybeGpuUsagePercent: Int?
    private var gpuPollingTickCount = 0
    private var isMetricsUpdateInProgress = false
    private var timer: Timer?
    private var metricsUpdateTask: Task<Void, Never>?
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
        syncLaunchAtLogin()
        updateMetrics()
        scheduleTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        metricsUpdateTask?.cancel()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updateAdaptiveTextContrastIfNeeded(force: true)
    }

    @objc private func updateMetrics() {
        guard !isMetricsUpdateInProgress else {
            return
        }

        let isGpuReadRequired = getIsGpuReadRequired()
        isMetricsUpdateInProgress = true
        metricsUpdateTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer {
                isMetricsUpdateInProgress = false
                metricsUpdateTask = nil
            }

            let metricsPollResult = await metricsPollingWorker.readMetrics(isGpuReadRequired: isGpuReadRequired)

            guard !Task.isCancelled else {
                return
            }

            apply(metricsPollResult: metricsPollResult)
        }
    }

    private func apply(metricsPollResult: MetricsPollResult) {
        maybeLatestSnapshot = metricsPollResult.snapshot

        if let gpuUsagePercent = metricsPollResult.maybeGpuUsagePercent {
            maybeGpuUsagePercent = gpuUsagePercent
        }

        updateAdaptiveTextContrastIfNeeded()
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

    private func getIsGpuReadRequired() -> Bool {
        guard configuration.isGpuEnabled else {
            maybeGpuUsagePercent = nil
            gpuPollingTickCount = 0
            return false
        }

        guard isStatusItemVisibleForGpuPolling() else {
            return false
        }

        gpuPollingTickCount += 1

        guard gpuPollingTickCount >= configuration.gpuPollingMultiplier else {
            return false
        }

        gpuPollingTickCount = 0

        return true
    }

    private func isStatusItemVisibleForGpuPolling() -> Bool {
        guard let maybeStatusButton = statusItem.button else {
            return false
        }

        return maybeStatusButton.window != nil && !maybeStatusButton.isHidden
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
        adaptiveTextContrastSampler.reset()
    }

    private func updateAdaptiveTextContrastIfNeeded(force: Bool = false) {
        guard configuration.isAutoTextContrastEnabled else {
            metricsView.adaptiveTextColor = nil
            return
        }

        metricsView.adaptiveTextColor = adaptiveTextContrastSampler.sampleTextColor(
            statusButton: statusItem.button,
            force: force
        )
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

    private func syncLaunchAtLogin() {
        launchAtLoginController.apply(isEnabled: configuration.isLaunchAtLoginEnabled)
    }

    @objc private func showSettings() {
        let settingsWindowController = settingsWindowController ?? SettingsWindowController(
            configuration: configuration,
            onChange: { [weak self] configuration in
                self?.apply(configuration: configuration)
            },
            onClose: { [weak self] in
                self?.settingsWindowController = nil
            }
        )
        self.settingsWindowController = settingsWindowController
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func apply(configuration newConfiguration: AppConfiguration) {
        let previousPollingIntervalInSeconds = configuration.pollingIntervalInSeconds
        let previousIsGpuEnabled = configuration.isGpuEnabled
        let previousGpuPollingMultiplier = configuration.gpuPollingMultiplier
        let previousIsAutoTextContrastEnabled = configuration.isAutoTextContrastEnabled
        let previousIsLaunchAtLoginEnabled = configuration.isLaunchAtLoginEnabled
        configuration = newConfiguration
        configurationStore.save(newConfiguration)
        metricsView.configuration = newConfiguration
        updateStatusItemSize()

        if previousIsGpuEnabled != newConfiguration.isGpuEnabled || previousGpuPollingMultiplier != newConfiguration.gpuPollingMultiplier {
            maybeGpuUsagePercent = nil
            gpuPollingTickCount = 0
        }

        if previousIsAutoTextContrastEnabled != newConfiguration.isAutoTextContrastEnabled {
            adaptiveTextContrastSampler.reset()
            updateAdaptiveTextContrastIfNeeded(force: true)
        }

        if previousIsLaunchAtLoginEnabled != newConfiguration.isLaunchAtLoginEnabled {
            syncLaunchAtLogin()
        }

        syncMetricsViewSnapshot()

        if previousPollingIntervalInSeconds != newConfiguration.pollingIntervalInSeconds {
            gpuPollingTickCount = 0
            scheduleTimer()
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

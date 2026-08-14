import AppKit
import GlanceBarCore

enum ContextMenuEntry: Equatable {
    case update(title: String)
    case metric(id: String, title: String, isEnabled: Bool)
    case separator
    case settings
    case quit
}

func getContextMenuEntries(
    isAutoUpdateEnabled: Bool,
    updateAvailability: UpdateAvailability,
    enabledMetricIDs: Set<String>
) -> [ContextMenuEntry] {
    let updateEntries = isAutoUpdateEnabled
        ? []
        : [ContextMenuEntry.update(title: getUpdateMenuTitle(availability: updateAvailability)), .separator]
    let metricEntries = availableMetrics.map { metricConfiguration in
        ContextMenuEntry.metric(
            id: metricConfiguration.id,
            title: metricConfiguration.title,
            isEnabled: enabledMetricIDs.contains(metricConfiguration.id)
        )
    }

    return updateEntries + metricEntries + [.separator, .settings, .quit]
}

func getEnabledMetricIDsAfterToggle(metricID: String, enabledMetricIDs: Set<String>) -> Set<String> {
    if enabledMetricIDs.contains(metricID) {
        return enabledMetricIDs.subtracting([metricID])
    }

    return enabledMetricIDs.union([metricID])
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let metricsPollingWorker = MetricsPollingWorker()
    private let metricsView = StatusMetricsView(frame: .zero)
    private let configurationStore: AppConfigurationStore
    private let adaptiveTextContrastSampler = AdaptiveTextContrastSampler()
    private let launchAtLoginController = LaunchAtLoginController()
    private lazy var updaterCoordinator = UpdaterCoordinator { [weak self] in
        self?.updaterStateDidChange()
    }
    private lazy var uninstallCoordinator = UninstallCoordinator(
        launchAtLoginController: launchAtLoginController
    )
    private var configuration: AppConfiguration
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
        rebuildMenu()
        syncLaunchAtLogin()
        updaterCoordinator.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        Task {
            await metricsPollingWorker.start(
                configuration: makeMetricsPollingConfiguration(),
                onSnapshot: { [weak self] snapshot in
                    self?.apply(snapshot: snapshot)
                }
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        Task {
            await metricsPollingWorker.stop()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updateAdaptiveTextContrastIfNeeded(force: true)
    }

    private func apply(snapshot: MetricsSnapshot) {
        metricsView.snapshot = snapshot
        updateAdaptiveTextContrastIfNeeded()
    }

    private func makeMetricsPollingConfiguration() -> MetricsPollingConfiguration {
        MetricsPollingConfiguration(
            enabledMetricIDs: configuration.enabledMetricIDs,
            pollingIntervalsByMetricID: configuration.pollingIntervalsByMetricID,
            isLowPowerModeAdjustmentActive: configuration.isLowPowerModePollingAdjustmentEnabled
                && ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    @objc private func powerStateDidChange() {
        Task {
            await metricsPollingWorker.update(configuration: makeMetricsPollingConfiguration())
        }
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
            metricsView.adaptiveColorsByRoleID = [:]
            return
        }

        guard let backgroundColor = adaptiveTextContrastSampler.sampleBackgroundColor(
            statusButton: statusItem.button,
            force: force
        ) else {
            metricsView.adaptiveColorsByRoleID = [:]
            return
        }

        metricsView.adaptiveColorsByRoleID = colorRoles.reduce(into: [String: NSColor]()) {
            adaptiveColorsByRoleID,
            colorRole in
            adaptiveColorsByRoleID[colorRole.id] = getContrastAdjustedColor(
                color: getConfiguredColor(configuration: configuration, colorRoleID: colorRole.id),
                backgroundColor: backgroundColor
            )
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        for entry in getContextMenuEntries(
            isAutoUpdateEnabled: updaterCoordinator.isAutoUpdateEnabled,
            updateAvailability: updaterCoordinator.availability,
            enabledMetricIDs: configuration.enabledMetricIDs
        ) {
            if case let .update(title) = entry {
                let updateItem = NSMenuItem(title: title, action: #selector(checkForUpdates), keyEquivalent: "")
                updateItem.target = self
                menu.addItem(updateItem)
            } else if case let .metric(id, title, isEnabled) = entry {
                let metricItem = NSMenuItem(title: title, action: #selector(toggleMetric(_:)), keyEquivalent: "")
                metricItem.target = self
                metricItem.representedObject = id
                metricItem.state = isEnabled ? .on : .off
                menu.addItem(metricItem)
            } else if entry == .separator {
                menu.addItem(.separator())
            } else if entry == .settings {
                let settingsItem = NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ",")
                settingsItem.target = self
                menu.addItem(settingsItem)
            } else if entry == .quit {
                menu.addItem(NSMenuItem(
                    title: "Quit",
                    action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q"
                ))
            }
        }

        statusItem.menu = menu
    }

    private func updaterStateDidChange() {
        rebuildMenu()
        settingsWindowController?.update(
            configuration: configuration,
            isAutoUpdateEnabled: updaterCoordinator.isAutoUpdateEnabled
        )
    }

    @objc private func checkForUpdates() {
        updaterCoordinator.checkForUpdates()
    }

    @objc private func toggleMetric(_ sender: NSMenuItem) {
        guard let metricID = sender.representedObject as? String else {
            return
        }

        apply(configuration: AppConfiguration(
            isLaunchAtLoginEnabled: configuration.isLaunchAtLoginEnabled,
            enabledMetricIDs: getEnabledMetricIDsAfterToggle(
                metricID: metricID,
                enabledMetricIDs: configuration.enabledMetricIDs
            ),
            orderedMetricIDs: configuration.orderedMetricIDs,
            pollingIntervalsByMetricID: configuration.pollingIntervalsByMetricID,
            isLowPowerModePollingAdjustmentEnabled: configuration.isLowPowerModePollingAdjustmentEnabled,
            warningThresholdPercent: configuration.warningThresholdPercent,
            warningColorID: configuration.warningColorID,
            criticalThresholdPercent: configuration.criticalThresholdPercent,
            criticalColorID: configuration.criticalColorID,
            uploadColorID: configuration.uploadColorID,
            downloadColorID: configuration.downloadColorID,
            baseTextColorID: configuration.baseTextColorID,
            labelTextColorID: configuration.labelTextColorID,
            isAutoTextContrastEnabled: configuration.isAutoTextContrastEnabled,
            colorAdjustments: configuration.colorAdjustments
        ))
    }

    private func syncLaunchAtLogin() {
        launchAtLoginController.apply(isEnabled: configuration.isLaunchAtLoginEnabled)
    }

    @objc private func showSettings() {
        let settingsWindowController = settingsWindowController ?? SettingsWindowController(
            configuration: configuration,
            isAutoUpdateEnabled: updaterCoordinator.isAutoUpdateEnabled,
            onChange: { [weak self] configuration in
                self?.apply(configuration: configuration)
            },
            onAutoUpdateChange: { [weak self] isEnabled in
                self?.updaterCoordinator.setAutoUpdateEnabled(isEnabled)
            },
            onUninstall: { [weak self] in
                guard let self else {
                    return
                }

                uninstallCoordinator.confirmAndUninstall(
                    isLaunchAtLoginEnabled: configuration.isLaunchAtLoginEnabled,
                    window: self.settingsWindowController?.window
                )
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
        let previousIsAutoTextContrastEnabled = configuration.isAutoTextContrastEnabled
        let previousIsLaunchAtLoginEnabled = configuration.isLaunchAtLoginEnabled
        configuration = newConfiguration
        configurationStore.save(newConfiguration)
        metricsView.configuration = newConfiguration
        updateStatusItemSize()
        rebuildMenu()
        settingsWindowController?.update(configuration: newConfiguration)
        updateAdaptiveTextContrastIfNeeded(force: true)

        if previousIsAutoTextContrastEnabled != newConfiguration.isAutoTextContrastEnabled {
            adaptiveTextContrastSampler.reset()
            updateAdaptiveTextContrastIfNeeded(force: true)
        }

        if previousIsLaunchAtLoginEnabled != newConfiguration.isLaunchAtLoginEnabled {
            syncLaunchAtLogin()
        }

        Task {
            await metricsPollingWorker.update(configuration: makeMetricsPollingConfiguration())
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

private func getConfiguredColor(configuration: AppConfiguration, colorRoleID: String) -> NSColor {
    if colorRoleID == warningColorKey {
        return configuration.warningColor
    }

    if colorRoleID == criticalColorKey {
        return configuration.criticalColor
    }

    if colorRoleID == uploadColorKey {
        return configuration.uploadColor
    }

    if colorRoleID == downloadColorKey {
        return configuration.downloadColor
    }

    if colorRoleID == baseTextColorKey {
        return configuration.baseTextColor
    }

    return configuration.labelTextColor
}

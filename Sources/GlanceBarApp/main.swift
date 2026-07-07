import AppKit
import GlanceBarCore

private let metricsUpdateIntervalInSeconds: TimeInterval = 3
private let metricsTimerToleranceInSeconds: TimeInterval = 0.5

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: StatusMetricsView.preferredSize.width)
    private let metricsReader = SystemMetricsReader()
    private let metricsView = StatusMetricsView(frame: NSRect(origin: .zero, size: StatusMetricsView.preferredSize))
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusButton()
        statusItem.menu = makeMenu()
        updateMetrics()
        timer = Timer.scheduledTimer(
            timeInterval: metricsUpdateIntervalInSeconds,
            target: self,
            selector: #selector(updateMetrics),
            userInfo: nil,
            repeats: true
        )
        timer?.tolerance = metricsTimerToleranceInSeconds
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    @objc private func updateMetrics() {
        metricsView.snapshot = metricsReader.readSnapshot()
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
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

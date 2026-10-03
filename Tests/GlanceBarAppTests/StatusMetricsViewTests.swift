import AppKit
import GlanceBarCore
import Testing
@testable import GlanceBarApp

@MainActor
@Test func unchangedVisibleMetricsDoNotRequestRedraws() {
    let view = TrackingStatusMetricsView(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
    view.snapshot = MetricsSnapshot(cpuUsagePercent: 20, networkUploadBytesPerSecond: 10)
    view.invalidatedRects.removeAll()
    view.snapshot = MetricsSnapshot(cpuUsagePercent: 20, networkUploadBytesPerSecond: 11)

    #expect(view.invalidatedRects.isEmpty)

    view.adaptiveColorsByRoleID = [:]

    #expect(view.invalidatedRects.isEmpty)

    view.configuration = makeDefaultAppConfiguration()

    #expect(view.invalidatedRects.isEmpty)
}

@MainActor
@Test func changedVisibleMetricsAndColorsRequestRedraws() {
    let view = TrackingStatusMetricsView(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
    view.snapshot = MetricsSnapshot(cpuUsagePercent: 20)
    view.invalidatedRects.removeAll()
    view.snapshot = MetricsSnapshot(cpuUsagePercent: 21)

    #expect(view.invalidatedRects == [NSRect(x: 0, y: 0, width: 36, height: 24)])

    view.invalidatedRects.removeAll()
    view.adaptiveColorsByRoleID = [baseTextColorKey: .black]

    #expect(!view.invalidatedRects.isEmpty)

    view.invalidatedRects.removeAll()
    view.adaptiveColorsByRoleID = [baseTextColorKey: .black]

    #expect(view.invalidatedRects.isEmpty)

    view.snapshot = MetricsSnapshot(cpuUsagePercent: nil)

    #expect(!view.invalidatedRects.isEmpty)
}

@MainActor
@Test func disabledMetricChangesDoNotRequestRedraws() throws {
    let suiteName = "dev.nitodeco.glancebar.tests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
    userDefaults.set([cpuMetricID], forKey: "enabledMetricIDs")
    let view = TrackingStatusMetricsView(frame: NSRect(x: 0, y: 0, width: 36, height: 24))
    view.configuration = AppConfigurationStore(userDefaults: userDefaults).load()
    view.snapshot = MetricsSnapshot(cpuUsagePercent: 20, ramUsagePercent: 50)
    view.invalidatedRects.removeAll()
    view.snapshot = MetricsSnapshot(cpuUsagePercent: 20, ramUsagePercent: 51)

    #expect(view.invalidatedRects.isEmpty)
}

@MainActor
private final class TrackingStatusMetricsView: StatusMetricsView {
    var invalidatedRects: [NSRect] = []

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        invalidatedRects.append(invalidRect)
        super.setNeedsDisplay(invalidRect)
    }
}

@MainActor
@Test func metricReorderingAndThresholdChangesInvalidateAffectedColumns() throws {
    let suiteName = "dev.nitodeco.glancebar.tests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
    let defaultConfiguration = makeDefaultAppConfiguration()
    userDefaults.set(defaultConfiguration.criticalThresholdPercent, forKey: "criticalThresholdPercent")
    userDefaults.set(defaultConfiguration.warningThresholdPercent, forKey: "warningThresholdPercent")
    userDefaults.set([cpuMetricID, ramMetricID], forKey: "enabledMetricIDs")
    let store = AppConfigurationStore(userDefaults: userDefaults)
    let view = TrackingStatusMetricsView(frame: NSRect(x: 0, y: 0, width: 72, height: 24))
    view.configuration = store.load()
    view.snapshot = MetricsSnapshot(cpuUsagePercent: 76, ramUsagePercent: 50)
    view.invalidatedRects.removeAll()
    userDefaults.set(80, forKey: "warningThresholdPercent")
    view.configuration = store.load()

    #expect(view.invalidatedRects == [NSRect(x: 0, y: 0, width: 36, height: 24)])

    view.invalidatedRects.removeAll()
    userDefaults.set([ramMetricID, cpuMetricID], forKey: "orderedMetricIDs")
    view.configuration = store.load()

    #expect(view.invalidatedRects == [
        NSRect(x: 0, y: 0, width: 36, height: 24),
        NSRect(x: 36, y: 0, width: 36, height: 24)
    ])
}

import Testing
@testable import GlanceBarApp

@Test func buildsContextMenuForAutomaticAndManualUpdates() {
    let enabledMetricIDs = Set([cpuMetricID, ramMetricID])
    let automaticEntries = getContextMenuEntries(
        isAutoUpdateEnabled: true,
        updateAvailability: .notAvailable,
        enabledMetricIDs: enabledMetricIDs
    )
    let manualEntries = getContextMenuEntries(
        isAutoUpdateEnabled: false,
        updateAvailability: .available,
        enabledMetricIDs: enabledMetricIDs
    )

    #expect(automaticEntries == [
        .metric(id: cpuMetricID, title: "CPU", isEnabled: true),
        .metric(id: gpuMetricID, title: "GPU", isEnabled: false),
        .metric(id: ramMetricID, title: "RAM", isEnabled: true),
        .metric(id: ssdMetricID, title: "SSD", isEnabled: false),
        .metric(id: networkMetricID, title: "Network", isEnabled: false),
        .separator,
        .settings,
        .quit
    ])
    #expect(manualEntries.prefix(2) == [.update(title: "Update available"), .separator])
    #expect(Array(manualEntries.dropFirst(2)) == automaticEntries)
}

@Test func togglesTheSameMetricStateForSettingsAndContextMenu() {
    let enabledMetricIDs = Set([cpuMetricID, gpuMetricID])
    let withNetworkEnabled = getEnabledMetricIDsAfterToggle(
        metricID: networkMetricID,
        enabledMetricIDs: enabledMetricIDs
    )
    let withCpuDisabled = getEnabledMetricIDsAfterToggle(
        metricID: cpuMetricID,
        enabledMetricIDs: withNetworkEnabled
    )

    #expect(withNetworkEnabled == Set([cpuMetricID, gpuMetricID, networkMetricID]))
    #expect(withCpuDisabled == Set([gpuMetricID, networkMetricID]))
}

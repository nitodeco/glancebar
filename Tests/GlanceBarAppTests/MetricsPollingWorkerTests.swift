import Foundation
import GlanceBarCore
import Testing
@testable import GlanceBarApp

private final class MetricsReaderSpy: MetricsReading, @unchecked Sendable {
    private let lock = NSLock()
    private var callCountByMetricID: [String: Int] = [:]
    private(set) var networkResetCount = 0

    func readCpuUsagePercent() -> Int? {
        record(metricID: cpuMetricID)

        return 10
    }

    func readGpuUsagePercent() -> Int? {
        record(metricID: gpuMetricID)

        return 20
    }

    func readRamUsagePercent() -> Int? {
        record(metricID: ramMetricID)

        return 30
    }

    func readSsdUsagePercent() -> Int? {
        record(metricID: ssdMetricID)

        return 40
    }

    func readNetworkThroughput(date: Date) -> NetworkThroughput? {
        record(metricID: networkMetricID)

        return NetworkThroughput(uploadBytesPerSecond: 50, downloadBytesPerSecond: 60)
    }

    func resetNetworkBaseline() {
        lock.lock()
        networkResetCount += 1
        lock.unlock()
    }

    func callCount(metricID: String) -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }

        return callCountByMetricID[metricID] ?? 0
    }

    private func record(metricID: String) {
        lock.lock()
        callCountByMetricID[metricID, default: 0] += 1
        lock.unlock()
    }
}

@MainActor
private final class SnapshotRecorder {
    private(set) var snapshots: [MetricsSnapshot] = []

    func append(_ snapshot: MetricsSnapshot) {
        snapshots.append(snapshot)
    }
}

@Test func calculatesEffectivePollingIntervalsForPowerState() {
    let standardConfiguration = MetricsPollingConfiguration(
        enabledMetricIDs: [cpuMetricID],
        pollingIntervalsByMetricID: [cpuMetricID: 3],
        isLowPowerModeAdjustmentActive: false
    )
    let lowPowerConfiguration = MetricsPollingConfiguration(
        enabledMetricIDs: [cpuMetricID],
        pollingIntervalsByMetricID: [cpuMetricID: 3],
        isLowPowerModeAdjustmentActive: true
    )

    #expect(getEffectivePollingIntervalInSeconds(metricID: cpuMetricID, configuration: standardConfiguration) == 3)
    #expect(getEffectivePollingIntervalInSeconds(metricID: cpuMetricID, configuration: lowPowerConfiguration) == 15)
}

@Test func returnsOnlyMetricsWhoseDeadlinesAreDue() {
    let now = Date(timeIntervalSince1970: 100)
    let dueMetricIDs = getDueMetricIDs(
        nextPollDateByMetricID: [
            cpuMetricID: now,
            gpuMetricID: now.addingTimeInterval(1),
            ramMetricID: now.addingTimeInterval(-1)
        ],
        date: now
    )

    #expect(dueMetricIDs == Set([cpuMetricID, ramMetricID]))
}

@Test func clearsMetricAfterThirdConsecutiveFailureAndRecoversImmediately() {
    let firstFailure = getMetricFailureUpdate(previousConsecutiveFailureCount: 0, isSuccessful: false)
    let secondFailure = getMetricFailureUpdate(
        previousConsecutiveFailureCount: firstFailure.consecutiveFailureCount,
        isSuccessful: false
    )
    let thirdFailure = getMetricFailureUpdate(
        previousConsecutiveFailureCount: secondFailure.consecutiveFailureCount,
        isSuccessful: false
    )
    let recovery = getMetricFailureUpdate(
        previousConsecutiveFailureCount: thirdFailure.consecutiveFailureCount,
        isSuccessful: true
    )

    #expect(!firstFailure.shouldClearMetric)
    #expect(!secondFailure.shouldClearMetric)
    #expect(thirdFailure.shouldClearMetric)
    #expect(recovery.consecutiveFailureCount == 0)
    #expect(!recovery.shouldClearMetric)
}

@Test func formatsMissingPercentageAsHyphen() {
    #expect(formatPercentage(nil) == "-")
    #expect(formatPercentage(42) == "42%")
}

@Test func batchesDueMetricsWithoutPollingDisabledMetrics() async throws {
    let metricsReader = MetricsReaderSpy()
    let snapshotRecorder = SnapshotRecorder()
    let metricsPollingWorker = MetricsPollingWorker(metricsReader: metricsReader)
    await metricsPollingWorker.start(
        configuration: MetricsPollingConfiguration(
            enabledMetricIDs: [cpuMetricID, gpuMetricID],
            pollingIntervalsByMetricID: [cpuMetricID: 60, gpuMetricID: 60],
            isLowPowerModeAdjustmentActive: false
        ),
        onSnapshot: { snapshot in
            snapshotRecorder.append(snapshot)
        }
    )

    try await Task.sleep(for: .milliseconds(100))
    await metricsPollingWorker.stop()

    #expect(metricsReader.callCount(metricID: cpuMetricID) == 1)
    #expect(metricsReader.callCount(metricID: gpuMetricID) == 1)
    #expect(metricsReader.callCount(metricID: ramMetricID) == 0)
    #expect(metricsReader.callCount(metricID: ssdMetricID) == 0)
    #expect(metricsReader.callCount(metricID: networkMetricID) == 0)
    #expect(await snapshotRecorder.snapshots.count == 1)
}

@Test func reconfigurationClearsDisabledMetricsAndPollsChangedIntervalsImmediately() async throws {
    let metricsReader = MetricsReaderSpy()
    let snapshotRecorder = SnapshotRecorder()
    let metricsPollingWorker = MetricsPollingWorker(metricsReader: metricsReader)
    await metricsPollingWorker.start(
        configuration: MetricsPollingConfiguration(
            enabledMetricIDs: [cpuMetricID],
            pollingIntervalsByMetricID: [cpuMetricID: 60],
            isLowPowerModeAdjustmentActive: false
        ),
        onSnapshot: { snapshot in
            snapshotRecorder.append(snapshot)
        }
    )
    try await Task.sleep(for: .milliseconds(100))

    await metricsPollingWorker.update(configuration: MetricsPollingConfiguration(
        enabledMetricIDs: [gpuMetricID],
        pollingIntervalsByMetricID: [gpuMetricID: 30],
        isLowPowerModeAdjustmentActive: false
    ))
    try await Task.sleep(for: .milliseconds(100))
    await metricsPollingWorker.stop()

    #expect(metricsReader.callCount(metricID: cpuMetricID) == 1)
    #expect(metricsReader.callCount(metricID: gpuMetricID) == 1)
    #expect(await snapshotRecorder.snapshots.last?.cpuUsagePercent == nil)
    #expect(await snapshotRecorder.snapshots.last?.gpuUsagePercent == 20)
}

@Test func stoppingSchedulerCancelsFuturePolling() async throws {
    let metricsReader = MetricsReaderSpy()
    let metricsPollingWorker = MetricsPollingWorker(metricsReader: metricsReader)
    await metricsPollingWorker.start(
        configuration: MetricsPollingConfiguration(
            enabledMetricIDs: [cpuMetricID],
            pollingIntervalsByMetricID: [cpuMetricID: 0.02],
            isLowPowerModeAdjustmentActive: false
        ),
        onSnapshot: { _ in }
    )
    try await Task.sleep(for: .milliseconds(80))
    await metricsPollingWorker.stop()
    let callCountAfterStop = metricsReader.callCount(metricID: cpuMetricID)
    try await Task.sleep(for: .milliseconds(80))

    #expect(callCountAfterStop > 1)
    #expect(metricsReader.callCount(metricID: cpuMetricID) == callCountAfterStop)
}

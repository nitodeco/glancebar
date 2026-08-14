import Foundation
import GlanceBarCore

private let failedPollsBeforeClearingMetric = 3

struct MetricsPollingConfiguration: Equatable, Sendable {
    let enabledMetricIDs: Set<String>
    let pollingIntervalsByMetricID: [String: TimeInterval]
    let isLowPowerModeAdjustmentActive: Bool
}

protocol MetricsReading: AnyObject {
    func readCpuUsagePercent() -> Int?
    func readGpuUsagePercent() -> Int?
    func readRamUsagePercent() -> Int?
    func readSsdUsagePercent() -> Int?
    func readNetworkThroughput(date: Date) -> NetworkThroughput?
    func resetNetworkBaseline()
}

extension SystemMetricsReader: MetricsReading {}

actor MetricsPollingWorker {
    private let metricsReader: MetricsReading
    private var configuration = MetricsPollingConfiguration(
        enabledMetricIDs: [],
        pollingIntervalsByMetricID: [:],
        isLowPowerModeAdjustmentActive: false
    )
    private var consecutiveFailureCountByMetricID: [String: Int] = [:]
    private var nextPollDateByMetricID: [String: Date] = [:]
    private var snapshot = MetricsSnapshot()
    private var pollingTask: Task<Void, Never>?
    private var onSnapshot: (@MainActor @Sendable (MetricsSnapshot) -> Void)?

    init(metricsReader: MetricsReading = SystemMetricsReader()) {
        self.metricsReader = metricsReader
    }

    func start(
        configuration: MetricsPollingConfiguration,
        onSnapshot: @escaping @MainActor @Sendable (MetricsSnapshot) -> Void
    ) {
        self.onSnapshot = onSnapshot
        apply(configuration: configuration, isInitialConfiguration: true)
        startPollingTask()
    }

    func update(configuration: MetricsPollingConfiguration) async {
        apply(configuration: configuration, isInitialConfiguration: false)
        pollingTask?.cancel()
        startPollingTask()
        await publishSnapshot()
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        onSnapshot = nil
    }

    private func startPollingTask() {
        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
    }

    private func runPollingLoop() async {
        while !Task.isCancelled {
            let now = Date()
            let dueMetricIDs = getDueMetricIDs(nextPollDateByMetricID: nextPollDateByMetricID, date: now)

            if dueMetricIDs.isEmpty {
                guard let nextPollDate = nextPollDateByMetricID.values.min() else {
                    return
                }

                do {
                    try await Task.sleep(for: .seconds(max(0, nextPollDate.timeIntervalSinceNow)))
                } catch {
                    return
                }

                continue
            }

            poll(metricIDs: dueMetricIDs, date: now)

            guard !Task.isCancelled else {
                return
            }

            for metricID in dueMetricIDs where configuration.enabledMetricIDs.contains(metricID) {
                nextPollDateByMetricID[metricID] = now.addingTimeInterval(
                    getEffectivePollingIntervalInSeconds(metricID: metricID, configuration: configuration)
                )
            }

            await publishSnapshot()
        }
    }

    private func apply(configuration newConfiguration: MetricsPollingConfiguration, isInitialConfiguration: Bool) {
        let previousEnabledMetricIDs = configuration.enabledMetricIDs
        let disabledMetricIDs = previousEnabledMetricIDs.subtracting(newConfiguration.enabledMetricIDs)
        let enabledMetricIDs = newConfiguration.enabledMetricIDs.subtracting(previousEnabledMetricIDs)
        let hasPowerModeAdjustmentChanged = configuration.isLowPowerModeAdjustmentActive
            != newConfiguration.isLowPowerModeAdjustmentActive
        let changedIntervalMetricIDs = newConfiguration.enabledMetricIDs.filter { metricID in
            configuration.pollingIntervalsByMetricID[metricID] != newConfiguration.pollingIntervalsByMetricID[metricID]
        }

        configuration = newConfiguration

        for metricID in disabledMetricIDs {
            clear(metricID: metricID)
            nextPollDateByMetricID.removeValue(forKey: metricID)
            consecutiveFailureCountByMetricID.removeValue(forKey: metricID)
        }

        if disabledMetricIDs.contains(networkMetricID) {
            metricsReader.resetNetworkBaseline()
        }

        let now = Date()
        let immediatelyDueMetricIDs = isInitialConfiguration
            ? newConfiguration.enabledMetricIDs
            : enabledMetricIDs.union(changedIntervalMetricIDs)

        for metricID in immediatelyDueMetricIDs {
            nextPollDateByMetricID[metricID] = now
        }

        if hasPowerModeAdjustmentChanged, !isInitialConfiguration {
            for metricID in newConfiguration.enabledMetricIDs {
                nextPollDateByMetricID[metricID] = now.addingTimeInterval(
                    getEffectivePollingIntervalInSeconds(metricID: metricID, configuration: newConfiguration)
                )
            }
        }
    }

    private func poll(metricIDs: Set<String>, date: Date) {
        for metricID in metricIDs where configuration.enabledMetricIDs.contains(metricID) {
            if metricID == cpuMetricID {
                apply(percent: metricsReader.readCpuUsagePercent(), metricID: metricID)
            } else if metricID == gpuMetricID {
                apply(percent: metricsReader.readGpuUsagePercent(), metricID: metricID)
            } else if metricID == ramMetricID {
                apply(percent: metricsReader.readRamUsagePercent(), metricID: metricID)
            } else if metricID == ssdMetricID {
                apply(percent: metricsReader.readSsdUsagePercent(), metricID: metricID)
            } else if metricID == networkMetricID {
                apply(networkThroughput: metricsReader.readNetworkThroughput(date: date))
            }
        }
    }

    private func apply(percent: Int?, metricID: String) {
        guard let percent else {
            recordFailure(metricID: metricID)
            return
        }

        consecutiveFailureCountByMetricID[metricID] = 0

        if metricID == cpuMetricID {
            snapshot = replacing(snapshot: snapshot, cpuUsagePercent: percent)
        } else if metricID == gpuMetricID {
            snapshot = replacing(snapshot: snapshot, gpuUsagePercent: percent)
        } else if metricID == ramMetricID {
            snapshot = replacing(snapshot: snapshot, ramUsagePercent: percent)
        } else if metricID == ssdMetricID {
            snapshot = replacing(snapshot: snapshot, ssdUsagePercent: percent)
        }
    }

    private func apply(networkThroughput: NetworkThroughput?) {
        guard let networkThroughput else {
            recordFailure(metricID: networkMetricID)
            return
        }

        consecutiveFailureCountByMetricID[networkMetricID] = 0
        snapshot = replacing(
            snapshot: snapshot,
            networkUploadBytesPerSecond: networkThroughput.uploadBytesPerSecond,
            networkDownloadBytesPerSecond: networkThroughput.downloadBytesPerSecond
        )
    }

    private func recordFailure(metricID: String) {
        let failureUpdate = getMetricFailureUpdate(
            previousConsecutiveFailureCount: consecutiveFailureCountByMetricID[metricID] ?? 0,
            isSuccessful: false
        )
        consecutiveFailureCountByMetricID[metricID] = failureUpdate.consecutiveFailureCount

        if failureUpdate.shouldClearMetric {
            clear(metricID: metricID)
        }
    }

    private func clear(metricID: String) {
        snapshot = clearing(snapshot: snapshot, metricID: metricID)
    }

    private func publishSnapshot() async {
        guard let onSnapshot else {
            return
        }

        await onSnapshot(snapshot)
    }
}

func getEffectivePollingIntervalInSeconds(
    metricID: String,
    configuration: MetricsPollingConfiguration
) -> TimeInterval {
    let pollingIntervalInSeconds = configuration.pollingIntervalsByMetricID[metricID]
        ?? minimumPollingIntervalInSeconds

    if configuration.isLowPowerModeAdjustmentActive {
        return pollingIntervalInSeconds * 5
    }

    return pollingIntervalInSeconds
}

func getDueMetricIDs(nextPollDateByMetricID: [String: Date], date: Date) -> Set<String> {
    Set(nextPollDateByMetricID.compactMap { metricID, nextPollDate in
        nextPollDate <= date ? metricID : nil
    })
}

func getMetricFailureUpdate(
    previousConsecutiveFailureCount: Int,
    isSuccessful: Bool
) -> (consecutiveFailureCount: Int, shouldClearMetric: Bool) {
    if isSuccessful {
        return (0, false)
    }

    let consecutiveFailureCount = previousConsecutiveFailureCount + 1

    return (
        consecutiveFailureCount,
        consecutiveFailureCount >= failedPollsBeforeClearingMetric
    )
}

private func replacing(
    snapshot: MetricsSnapshot,
    cpuUsagePercent: Int? = nil,
    gpuUsagePercent: Int? = nil,
    ramUsagePercent: Int? = nil,
    ssdUsagePercent: Int? = nil,
    networkUploadBytesPerSecond: UInt64? = nil,
    networkDownloadBytesPerSecond: UInt64? = nil
) -> MetricsSnapshot {
    MetricsSnapshot(
        cpuUsagePercent: cpuUsagePercent ?? snapshot.cpuUsagePercent,
        gpuUsagePercent: gpuUsagePercent ?? snapshot.gpuUsagePercent,
        ramUsagePercent: ramUsagePercent ?? snapshot.ramUsagePercent,
        ssdUsagePercent: ssdUsagePercent ?? snapshot.ssdUsagePercent,
        networkUploadBytesPerSecond: networkUploadBytesPerSecond ?? snapshot.networkUploadBytesPerSecond,
        networkDownloadBytesPerSecond: networkDownloadBytesPerSecond ?? snapshot.networkDownloadBytesPerSecond
    )
}

private func clearing(snapshot: MetricsSnapshot, metricID: String) -> MetricsSnapshot {
    MetricsSnapshot(
        cpuUsagePercent: metricID == cpuMetricID ? nil : snapshot.cpuUsagePercent,
        gpuUsagePercent: metricID == gpuMetricID ? nil : snapshot.gpuUsagePercent,
        ramUsagePercent: metricID == ramMetricID ? nil : snapshot.ramUsagePercent,
        ssdUsagePercent: metricID == ssdMetricID ? nil : snapshot.ssdUsagePercent,
        networkUploadBytesPerSecond: metricID == networkMetricID ? nil : snapshot.networkUploadBytesPerSecond,
        networkDownloadBytesPerSecond: metricID == networkMetricID ? nil : snapshot.networkDownloadBytesPerSecond
    )
}

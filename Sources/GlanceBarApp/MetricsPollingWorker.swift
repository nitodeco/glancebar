import GlanceBarCore

struct MetricsPollResult: Sendable {
    let snapshot: MetricsSnapshot
    let maybeGpuUsagePercent: Int?
}

actor MetricsPollingWorker {
    private let metricsReader = SystemMetricsReader()

    func readMetrics(isGpuReadRequired: Bool) -> MetricsPollResult {
        MetricsPollResult(
            snapshot: metricsReader.readSnapshot(),
            maybeGpuUsagePercent: isGpuReadRequired ? metricsReader.readGpuUsagePercent() : nil
        )
    }
}

import Foundation
import Testing
@testable import GlanceBarCore

private final class ProbeSequence<Value> {
    private var iterator: IndexingIterator<[Value?]>

    init(_ values: [Value?]) {
        iterator = values.makeIterator()
    }

    func next() -> Value? {
        iterator.next() ?? nil
    }
}

@Test func cachesSsdUsageForConfiguredInterval() {
    var ssdReadCount = 0
    let reader = SystemMetricsReader(
        ssdUpdateIntervalInSeconds: 30,
        probe: SystemMetricsProbe(
            readRamUsagePercent: { 72 },
            readSsdUsagePercent: {
                ssdReadCount += 1

                return ssdReadCount * 10
            },
            readGpuUsagePercent: { 0 },
            readNetworkCounters: {
                NetworkCounters(uploadBytes: 0, downloadBytes: 0)
            }
        )
    )

    let firstSnapshot = reader.readSnapshot(date: Date(timeIntervalSince1970: 0))
    let cachedSnapshot = reader.readSnapshot(date: Date(timeIntervalSince1970: 29))
    let refreshedSnapshot = reader.readSnapshot(date: Date(timeIntervalSince1970: 30))

    #expect(firstSnapshot.ramUsagePercent == 72)
    #expect(firstSnapshot.ssdUsagePercent == 10)
    #expect(cachedSnapshot.ssdUsagePercent == 10)
    #expect(refreshedSnapshot.ssdUsagePercent == 20)
    #expect(ssdReadCount == 2)
}

@Test func calculatesNetworkThroughputFromCounterDeltas() {
    var networkCounters = [
        NetworkCounters(uploadBytes: 1_000, downloadBytes: 2_000),
        NetworkCounters(uploadBytes: 1_600, downloadBytes: 3_200)
    ]
    let reader = SystemMetricsReader(
        probe: SystemMetricsProbe(
            readRamUsagePercent: { 0 },
            readSsdUsagePercent: { 0 },
            readGpuUsagePercent: { 0 },
            readNetworkCounters: {
                networkCounters.removeFirst()
            }
        )
    )

    let firstSnapshot = reader.readSnapshot(date: Date(timeIntervalSince1970: 0))
    let secondSnapshot = reader.readSnapshot(date: Date(timeIntervalSince1970: 3))

    #expect(firstSnapshot.networkUploadBytesPerSecond == 0)
    #expect(firstSnapshot.networkDownloadBytesPerSecond == 0)
    #expect(secondSnapshot.networkUploadBytesPerSecond == 200)
    #expect(secondSnapshot.networkDownloadBytesPerSecond == 400)
}

@Test func readsGpuUsageFromProbe() {
    let reader = SystemMetricsReader(
        probe: SystemMetricsProbe(
            readRamUsagePercent: { 0 },
            readSsdUsagePercent: { 0 },
            readGpuUsagePercent: { 42 },
            readNetworkCounters: {
                NetworkCounters(uploadBytes: 0, downloadBytes: 0)
            }
        )
    )

    #expect(reader.readGpuUsagePercent() == 42)
}

@Test func calculatesCpuTickDeltaAcrossSignedBoundaryAndRollover() {
    #expect(getTickDelta(from: UInt32(Int32.max), to: UInt32(bitPattern: Int32.min)) == 1)
    #expect(getTickDelta(from: UInt32.max, to: 0) == 1)
}

@Test func validatesCpuTickBufferShape() {
    #expect(hasValidCpuTickBufferShape(tickCount: 32, processorCount: 8, cpuLoadInfoCount: 4))
    #expect(!hasValidCpuTickBufferShape(tickCount: 31, processorCount: 8, cpuLoadInfoCount: 4))
    #expect(!hasValidCpuTickBufferShape(tickCount: 0, processorCount: 0, cpuLoadInfoCount: 4))
}

@Test func boundsNetworkThroughputConversion() {
    #expect(getBytesPerSecond(deltaBytes: 1_000, intervalInSeconds: 2) == 500)
    #expect(getBytesPerSecond(deltaBytes: UInt64.max, intervalInSeconds: .leastNonzeroMagnitude) == UInt64.max)
    #expect(getBytesPerSecond(deltaBytes: 1_000, intervalInSeconds: .nan) == 0)
}

@Test func preservesLastSuccessfulMetricsWhenProbesFail() {
    let ramUsagePercents = ProbeSequence([72, nil, nil])
    let ssdUsagePercents = ProbeSequence([64, nil, nil])
    let networkCounters = ProbeSequence([
        NetworkCounters(uploadBytes: 1_000, downloadBytes: 2_000),
        NetworkCounters(uploadBytes: 1_600, downloadBytes: 3_200),
        nil
    ])
    let reader = SystemMetricsReader(
        ssdUpdateIntervalInSeconds: 1,
        probe: SystemMetricsProbe(
            readRamUsagePercent: { ramUsagePercents.next() },
            readSsdUsagePercent: { ssdUsagePercents.next() },
            readGpuUsagePercent: { nil },
            readNetworkCounters: { networkCounters.next() }
        )
    )

    _ = reader.readSnapshot(date: Date(timeIntervalSince1970: 0))
    let successfulSnapshot = reader.readSnapshot(date: Date(timeIntervalSince1970: 1))
    let failedSnapshot = reader.readSnapshot(date: Date(timeIntervalSince1970: 2))

    #expect(failedSnapshot.ramUsagePercent == 72)
    #expect(failedSnapshot.ssdUsagePercent == 64)
    #expect(failedSnapshot.networkUploadBytesPerSecond == successfulSnapshot.networkUploadBytesPerSecond)
    #expect(failedSnapshot.networkDownloadBytesPerSecond == successfulSnapshot.networkDownloadBytesPerSecond)
}

@Test func preservesLastSuccessfulGpuMetricWhenProbeFails() {
    let gpuUsagePercents = ProbeSequence([42, nil])
    let reader = SystemMetricsReader(
        probe: SystemMetricsProbe(
            readRamUsagePercent: { 0 },
            readSsdUsagePercent: { 0 },
            readGpuUsagePercent: { gpuUsagePercents.next() },
            readNetworkCounters: {
                NetworkCounters(uploadBytes: 0, downloadBytes: 0)
            }
        )
    )

    #expect(reader.readGpuUsagePercent() == 42)
    #expect(reader.readGpuUsagePercent() == 42)
}

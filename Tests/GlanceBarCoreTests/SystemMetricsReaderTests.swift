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

@Test func readsOnlyRequestedMetricProbe() {
    var gpuReadCount = 0
    var ramReadCount = 0
    var ssdReadCount = 0
    var networkReadCount = 0
    let reader = SystemMetricsReader(
        probe: SystemMetricsProbe(
            readRamUsagePercent: {
                ramReadCount += 1
                return 72
            },
            readSsdUsagePercent: {
                ssdReadCount += 1
                return 64
            },
            readGpuUsagePercent: {
                gpuReadCount += 1
                return 42
            },
            readNetworkCounters: {
                networkReadCount += 1
                return NetworkCounters(uploadBytes: 0, downloadBytes: 0)
            }
        )
    )

    #expect(reader.readRamUsagePercent() == 72)
    #expect(ramReadCount == 1)
    #expect(gpuReadCount == 0)
    #expect(ssdReadCount == 0)
    #expect(networkReadCount == 0)
}

@Test func calculatesNetworkMeanFromElapsedCounterDelta() {
    let networkCounters = ProbeSequence([
        NetworkCounters(uploadBytes: 1_000, downloadBytes: 2_000),
        NetworkCounters(uploadBytes: 2_000, downloadBytes: 4_500)
    ])
    let reader = makeReader(readNetworkCounters: { networkCounters.next() })

    let firstThroughput = reader.readNetworkThroughput(date: Date(timeIntervalSince1970: 0))
    let secondThroughput = reader.readNetworkThroughput(date: Date(timeIntervalSince1970: 10))

    #expect(firstThroughput == NetworkThroughput(uploadBytesPerSecond: 0, downloadBytesPerSecond: 0))
    #expect(secondThroughput == NetworkThroughput(uploadBytesPerSecond: 100, downloadBytesPerSecond: 250))
}

@Test func resetsNetworkBaselineAfterDisable() {
    let networkCounters = ProbeSequence([
        NetworkCounters(uploadBytes: 1_000, downloadBytes: 2_000),
        NetworkCounters(uploadBytes: 5_000, downloadBytes: 8_000)
    ])
    let reader = makeReader(readNetworkCounters: { networkCounters.next() })

    _ = reader.readNetworkThroughput(date: Date(timeIntervalSince1970: 0))
    reader.resetNetworkBaseline()
    let throughputAfterReset = reader.readNetworkThroughput(date: Date(timeIntervalSince1970: 10))

    #expect(throughputAfterReset == NetworkThroughput(uploadBytesPerSecond: 0, downloadBytesPerSecond: 0))
}

@Test func returnsNilImmediatelyWhenProbeFails() {
    let ramUsagePercents = ProbeSequence([72, nil])
    let gpuUsagePercents = ProbeSequence([42, nil])
    let reader = SystemMetricsReader(
        probe: SystemMetricsProbe(
            readRamUsagePercent: { ramUsagePercents.next() },
            readSsdUsagePercent: { nil },
            readGpuUsagePercent: { gpuUsagePercents.next() },
            readNetworkCounters: { nil }
        )
    )

    #expect(reader.readRamUsagePercent() == 72)
    #expect(reader.readRamUsagePercent() == nil)
    #expect(reader.readGpuUsagePercent() == 42)
    #expect(reader.readGpuUsagePercent() == nil)
    #expect(reader.readSsdUsagePercent() == nil)
    #expect(reader.readNetworkThroughput() == nil)
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

private func makeReader(
    readNetworkCounters: @escaping () -> NetworkCounters?
) -> SystemMetricsReader {
    SystemMetricsReader(
        probe: SystemMetricsProbe(
            readRamUsagePercent: { 0 },
            readSsdUsagePercent: { 0 },
            readGpuUsagePercent: { 0 },
            readNetworkCounters: readNetworkCounters
        )
    )
}

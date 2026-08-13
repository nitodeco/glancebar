import Foundation
import Testing
@testable import GlanceBarCore

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

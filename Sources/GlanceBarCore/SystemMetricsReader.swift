import Darwin
import Foundation
import IOKit
import SystemConfiguration

private let dataVolumePath = "/System/Volumes/Data"
private let gpuAcceleratorClassName = "IOAccelerator"
private let gpuPerformanceStatisticsKey = "PerformanceStatistics"
private let gpuDeviceUtilizationKey = "Device Utilization %"
private let networkIpv4StateKey = "State:/Network/Global/IPv4"
private let networkIpv6StateKey = "State:/Network/Global/IPv6"
private let primaryInterfaceKey = "PrimaryInterface"

public final class SystemMetricsReader {
    private var maybePreviousCpuTicks: [UInt32]?
    private var maybePreviousNetworkCounters: NetworkCounters?
    private var maybePreviousNetworkDate: Date?
    private var failedMetricProbeIDs: Set<MetricProbeID> = []
    private let probe: SystemMetricsProbe

    public init() {
        probe = makeLiveSystemMetricsProbe()
    }

    init(probe: SystemMetricsProbe) {
        self.probe = probe
    }

    public func readCpuUsagePercent() -> Int? {
        recordProbeResult(metricProbeID: .cpu, value: readRawCpuUsagePercent())
    }

    public func readGpuUsagePercent() -> Int? {
        recordProbeResult(metricProbeID: .gpu, value: probe.readGpuUsagePercent())
    }

    public func readRamUsagePercent() -> Int? {
        recordProbeResult(metricProbeID: .ram, value: probe.readRamUsagePercent())
    }

    public func readSsdUsagePercent() -> Int? {
        recordProbeResult(metricProbeID: .ssd, value: probe.readSsdUsagePercent())
    }

    public func readNetworkThroughput(date: Date = Date()) -> NetworkThroughput? {
        recordProbeResult(metricProbeID: .network, value: readRawNetworkThroughput(date: date))
    }

    public func resetNetworkBaseline() {
        maybePreviousNetworkCounters = nil
        maybePreviousNetworkDate = nil
    }

    private func readRawCpuUsagePercent() -> Int? {
        var cpuInfo: processor_info_array_t?
        var processorCount: mach_msg_type_number_t = 0
        var cpuInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return nil
        }

        let vmSize = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vmSize)
        }

        let tickCount = Int(cpuInfoCount)
        let cpuLoadInfoCount = Int(CPU_STATE_MAX)

        guard hasValidCpuTickBufferShape(
            tickCount: tickCount,
            processorCount: Int(processorCount),
            cpuLoadInfoCount: cpuLoadInfoCount
        ) else {
            return nil
        }

        let ticks = (0..<tickCount).map { tickOffset in
            UInt32(bitPattern: cpuInfo[tickOffset])
        }

        guard let previousCpuTicks = maybePreviousCpuTicks, previousCpuTicks.count == ticks.count else {
            maybePreviousCpuTicks = ticks
            return 0
        }

        maybePreviousCpuTicks = ticks

        let processorUsages = stride(from: 0, to: ticks.count, by: cpuLoadInfoCount).compactMap { tickOffset -> CpuUsage? in
            let userIndex = tickOffset + Int(CPU_STATE_USER)
            let systemIndex = tickOffset + Int(CPU_STATE_SYSTEM)
            let niceIndex = tickOffset + Int(CPU_STATE_NICE)
            let idleIndex = tickOffset + Int(CPU_STATE_IDLE)
            guard
                let previousUserTick = getCpuTick(ticks: previousCpuTicks, index: userIndex),
                let userTick = getCpuTick(ticks: ticks, index: userIndex),
                let previousSystemTick = getCpuTick(ticks: previousCpuTicks, index: systemIndex),
                let systemTick = getCpuTick(ticks: ticks, index: systemIndex),
                let previousNiceTick = getCpuTick(ticks: previousCpuTicks, index: niceIndex),
                let niceTick = getCpuTick(ticks: ticks, index: niceIndex),
                let previousIdleTick = getCpuTick(ticks: previousCpuTicks, index: idleIndex),
                let idleTick = getCpuTick(ticks: ticks, index: idleIndex)
            else {
                return nil
            }

            let user = getTickDelta(from: previousUserTick, to: userTick)
            let system = getTickDelta(from: previousSystemTick, to: systemTick)
            let nice = getTickDelta(from: previousNiceTick, to: niceTick)
            let idle = getTickDelta(from: previousIdleTick, to: idleTick)
            let active = user + system + nice
            let total = active + idle

            return CpuUsage(activeTicks: active, totalTicks: total)
        }

        guard processorUsages.count == Int(processorCount) else {
            return nil
        }

        let totalActiveTicks = processorUsages.reduce(UInt64(0)) { acc, usage in
            acc + usage.activeTicks
        }
        let totalTicks = processorUsages.reduce(UInt64(0)) { acc, usage in
            acc + usage.totalTicks
        }

        guard totalTicks > 0 else {
            return 0
        }

        let usage = Double(totalActiveTicks) / Double(totalTicks)

        return clampPercent(Int((usage * 100).rounded()))
    }

    private func readRawNetworkThroughput(date: Date) -> NetworkThroughput? {
        guard let counters = probe.readNetworkCounters() else {
            return nil
        }
        defer {
            maybePreviousNetworkCounters = counters
            maybePreviousNetworkDate = date
        }

        guard
            let previousNetworkCounters = maybePreviousNetworkCounters,
            let previousNetworkDate = maybePreviousNetworkDate
        else {
            return NetworkThroughput(uploadBytesPerSecond: 0, downloadBytesPerSecond: 0)
        }

        let intervalInSeconds = date.timeIntervalSince(previousNetworkDate)

        guard intervalInSeconds > 0 else {
            return NetworkThroughput(uploadBytesPerSecond: 0, downloadBytesPerSecond: 0)
        }

        let uploadDeltaBytes = counters.uploadBytes >= previousNetworkCounters.uploadBytes ? counters.uploadBytes - previousNetworkCounters.uploadBytes : 0
        let downloadDeltaBytes = counters.downloadBytes >= previousNetworkCounters.downloadBytes ? counters.downloadBytes - previousNetworkCounters.downloadBytes : 0

        return NetworkThroughput(
            uploadBytesPerSecond: getBytesPerSecond(deltaBytes: uploadDeltaBytes, intervalInSeconds: intervalInSeconds),
            downloadBytesPerSecond: getBytesPerSecond(deltaBytes: downloadDeltaBytes, intervalInSeconds: intervalInSeconds)
        )
    }

    private func recordProbeFailure(metricProbeID: MetricProbeID) {
        guard failedMetricProbeIDs.insert(metricProbeID).inserted else {
            return
        }

        NSLog("Metric probe failed: %@", metricProbeID.rawValue)
    }

    private func recordProbeRecovery(metricProbeID: MetricProbeID) {
        guard failedMetricProbeIDs.remove(metricProbeID) != nil else {
            return
        }

        NSLog("Metric probe recovered: %@", metricProbeID.rawValue)
    }

    private func recordProbeResult<Value>(metricProbeID: MetricProbeID, value: Value?) -> Value? {
        if value == nil {
            recordProbeFailure(metricProbeID: metricProbeID)
        } else {
            recordProbeRecovery(metricProbeID: metricProbeID)
        }

        return value
    }
}

struct SystemMetricsProbe {
    let readRamUsagePercent: () -> Int?
    let readSsdUsagePercent: () -> Int?
    let readGpuUsagePercent: () -> Int?
    let readNetworkCounters: () -> NetworkCounters?
}

struct NetworkCounters {
    let uploadBytes: UInt64
    let downloadBytes: UInt64
}

public struct NetworkThroughput: Equatable, Sendable {
    public let uploadBytesPerSecond: UInt64
    public let downloadBytesPerSecond: UInt64

    public init(uploadBytesPerSecond: UInt64, downloadBytesPerSecond: UInt64) {
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.downloadBytesPerSecond = downloadBytesPerSecond
    }
}

private struct CpuUsage {
    let activeTicks: UInt64
    let totalTicks: UInt64
}

private enum MetricProbeID: String {
    case cpu
    case gpu
    case network
    case ram
    case ssd
}

private func clampPercent(_ percent: Int) -> Int {
    min(max(percent, 0), 100)
}

func hasValidCpuTickBufferShape(tickCount: Int, processorCount: Int, cpuLoadInfoCount: Int) -> Bool {
    processorCount > 0
        && cpuLoadInfoCount > 0
        && tickCount == processorCount * cpuLoadInfoCount
}

func getTickDelta(from previousTick: UInt32, to tick: UInt32) -> UInt64 {
    UInt64(tick &- previousTick)
}

func getBytesPerSecond(deltaBytes: UInt64, intervalInSeconds: TimeInterval) -> UInt64 {
    guard intervalInSeconds.isFinite, intervalInSeconds > 0 else {
        return 0
    }

    let bytesPerSecond = Double(deltaBytes) / intervalInSeconds

    guard bytesPerSecond.isFinite else {
        return UInt64.max
    }

    if bytesPerSecond >= Double(UInt64.max) {
        return UInt64.max
    }

    return UInt64(bytesPerSecond)
}

private func getCpuTick(ticks: [UInt32], index: Int) -> UInt32? {
    ticks.enumerated().first { tickIndex, _ in
        tickIndex == index
    }?.element
}

private func readLiveRamUsagePercent() -> Int? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &stats) { statsPointer in
        statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
            host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
        }
    }

    guard result == KERN_SUCCESS else {
        return nil
    }

    let activePages = UInt64(stats.active_count)
    let wiredPages = UInt64(stats.wire_count)
    let compressedPages = UInt64(stats.compressor_page_count)
    let inactivePages = UInt64(stats.inactive_count)
    let freePages = UInt64(stats.free_count)
    let speculativePages = UInt64(stats.speculative_count)
    let usedPages = activePages + wiredPages + compressedPages
    let totalPages = usedPages + inactivePages + freePages + speculativePages

    guard totalPages > 0 else {
        return nil
    }

    return clampPercent(Int((Double(usedPages) / Double(totalPages) * 100).rounded()))
}

private func readLiveSsdUsagePercent() -> Int? {
    do {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: dataVolumePath)
        let maybeFreeBytes = attributes[.systemFreeSize] as? NSNumber
        let maybeTotalBytes = attributes[.systemSize] as? NSNumber
        let freeBytes = maybeFreeBytes?.uint64Value ?? 0
        let totalBytes = maybeTotalBytes?.uint64Value ?? 0

        guard totalBytes > 0, totalBytes >= freeBytes else {
            return nil
        }

        return clampPercent(Int((Double(totalBytes - freeBytes) / Double(totalBytes) * 100).rounded()))
    } catch {
        return nil
    }
}

private func readLiveGpuUsagePercent() -> Int? {
    guard let matchingDictionary = IOServiceMatching(gpuAcceleratorClassName) else {
        return nil
    }

    var iterator = io_iterator_t()
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator)

    guard result == KERN_SUCCESS else {
        return nil
    }

    defer {
        IOObjectRelease(iterator)
    }

    var utilizationPercents: [Int] = []
    var service = IOIteratorNext(iterator)

    while service != 0 {
        if let maybeUtilizationPercent = readGpuUtilizationPercent(service: service) {
            utilizationPercents.append(maybeUtilizationPercent)
        }

        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }

    return utilizationPercents.max()
}

private func readGpuUtilizationPercent(service: io_object_t) -> Int? {
    guard
        let maybeStatistics = IORegistryEntryCreateCFProperty(
            service,
            gpuPerformanceStatisticsKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any],
        let maybeUtilizationPercent = maybeStatistics[gpuDeviceUtilizationKey] as? NSNumber
    else {
        return nil
    }

    return clampPercent(maybeUtilizationPercent.intValue)
}

private func readLiveNetworkCounters() -> NetworkCounters? {
    var maybeInterfaces: UnsafeMutablePointer<ifaddrs>?
    var uploadBytes: UInt64 = 0
    var downloadBytes: UInt64 = 0
    let activeInterfaceNames = getActiveNetworkInterfaceNames()

    guard getifaddrs(&maybeInterfaces) == 0, let interfaces = maybeInterfaces else {
        return nil
    }

    defer {
        freeifaddrs(interfaces)
    }

    var maybeInterface = Optional(interfaces)

    while let interface = maybeInterface {
        let flags = Int32(interface.pointee.ifa_flags)
        let isUp = (flags & IFF_UP) != 0
        let isLoopback = (flags & IFF_LOOPBACK) != 0
        let maybeAddress = interface.pointee.ifa_addr
        let interfaceName = String(cString: interface.pointee.ifa_name)
        let isActiveInterface = activeInterfaceNames.contains(interfaceName)

        if isUp, !isLoopback, isActiveInterface, maybeAddress?.pointee.sa_family == UInt8(AF_LINK) {
            let maybeData = interface.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            uploadBytes += UInt64(maybeData?.pointee.ifi_obytes ?? 0)
            downloadBytes += UInt64(maybeData?.pointee.ifi_ibytes ?? 0)
        }

        maybeInterface = interface.pointee.ifa_next
    }

    return NetworkCounters(uploadBytes: uploadBytes, downloadBytes: downloadBytes)
}

private func getActiveNetworkInterfaceNames() -> Set<String> {
    let maybeIpv4State = SCDynamicStoreCopyValue(nil, networkIpv4StateKey as CFString) as? [String: Any]
    let maybeIpv6State = SCDynamicStoreCopyValue(nil, networkIpv6StateKey as CFString) as? [String: Any]
    let maybeIpv4InterfaceName = maybeIpv4State?[primaryInterfaceKey] as? String
    let maybeIpv6InterfaceName = maybeIpv6State?[primaryInterfaceKey] as? String
    let interfaceNames = [maybeIpv4InterfaceName, maybeIpv6InterfaceName].compactMap { $0 }

    return Set(interfaceNames)
}

private func makeLiveSystemMetricsProbe() -> SystemMetricsProbe {
    SystemMetricsProbe(
        readRamUsagePercent: readLiveRamUsagePercent,
        readSsdUsagePercent: readLiveSsdUsagePercent,
        readGpuUsagePercent: readLiveGpuUsagePercent,
        readNetworkCounters: readLiveNetworkCounters
    )
}

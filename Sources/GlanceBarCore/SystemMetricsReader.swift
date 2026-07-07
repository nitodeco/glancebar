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
    private var maybePreviousCpuTicks: [integer_t]?
    private var maybePreviousNetworkCounters: NetworkCounters?
    private var maybePreviousNetworkDate: Date?
    private var cachedSsdUsagePercent: Int = 0
    private var lastSsdUpdateDate: Date = .distantPast
    private let ssdUpdateIntervalInSeconds: TimeInterval
    private let probe: SystemMetricsProbe

    public init(ssdUpdateIntervalInSeconds: TimeInterval = 30) {
        self.ssdUpdateIntervalInSeconds = ssdUpdateIntervalInSeconds
        probe = makeLiveSystemMetricsProbe()
    }

    init(ssdUpdateIntervalInSeconds: TimeInterval = 30, probe: SystemMetricsProbe) {
        self.ssdUpdateIntervalInSeconds = ssdUpdateIntervalInSeconds
        self.probe = probe
    }

    public func readSnapshot(date: Date = Date()) -> MetricsSnapshot {
        let cpuUsagePercent = readCpuUsagePercent()
        let ramUsagePercent = probe.readRamUsagePercent()
        let networkThroughput = readNetworkThroughput(date: date)

        if date.timeIntervalSince(lastSsdUpdateDate) >= ssdUpdateIntervalInSeconds {
            cachedSsdUsagePercent = probe.readSsdUsagePercent()
            lastSsdUpdateDate = date
        }

        return MetricsSnapshot(
            cpuUsagePercent: cpuUsagePercent,
            ramUsagePercent: ramUsagePercent,
            ssdUsagePercent: cachedSsdUsagePercent,
            networkUploadBytesPerSecond: networkThroughput.uploadBytesPerSecond,
            networkDownloadBytesPerSecond: networkThroughput.downloadBytesPerSecond
        )
    }

    public func readGpuUsagePercent() -> Int {
        probe.readGpuUsagePercent() ?? 0
    }

    private func readCpuUsagePercent() -> Int {
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
            return 0
        }

        let tickCount = Int(cpuInfoCount)
        let ticks = (0..<tickCount).map { cpuInfo[$0] }
        let vmSize = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vmSize)

        guard let previousCpuTicks = maybePreviousCpuTicks, previousCpuTicks.count == ticks.count else {
            maybePreviousCpuTicks = ticks
            return 0
        }

        maybePreviousCpuTicks = ticks

        let cpuLoadInfoCount = Int(CPU_STATE_MAX)
        let processorUsages = stride(from: 0, to: ticks.count, by: cpuLoadInfoCount).map { tickOffset in
            let userIndex = tickOffset + Int(CPU_STATE_USER)
            let systemIndex = tickOffset + Int(CPU_STATE_SYSTEM)
            let niceIndex = tickOffset + Int(CPU_STATE_NICE)
            let idleIndex = tickOffset + Int(CPU_STATE_IDLE)
            let user = tickDelta(from: previousCpuTicks[userIndex], to: ticks[userIndex])
            let system = tickDelta(from: previousCpuTicks[systemIndex], to: ticks[systemIndex])
            let nice = tickDelta(from: previousCpuTicks[niceIndex], to: ticks[niceIndex])
            let idle = tickDelta(from: previousCpuTicks[idleIndex], to: ticks[idleIndex])
            let active = user + system + nice
            let total = active + idle

            return CpuUsage(activeTicks: active, totalTicks: total)
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

    private func readNetworkThroughput(date: Date) -> NetworkThroughput {
        let counters = probe.readNetworkCounters()
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
            uploadBytesPerSecond: UInt64(Double(uploadDeltaBytes) / intervalInSeconds),
            downloadBytesPerSecond: UInt64(Double(downloadDeltaBytes) / intervalInSeconds)
        )
    }
}

struct SystemMetricsProbe {
    let readRamUsagePercent: () -> Int
    let readSsdUsagePercent: () -> Int
    let readGpuUsagePercent: () -> Int?
    let readNetworkCounters: () -> NetworkCounters
}

struct NetworkCounters {
    let uploadBytes: UInt64
    let downloadBytes: UInt64
}

struct NetworkThroughput {
    let uploadBytesPerSecond: UInt64
    let downloadBytesPerSecond: UInt64
}

private struct CpuUsage {
    let activeTicks: UInt64
    let totalTicks: UInt64
}

private func clampPercent(_ percent: Int) -> Int {
    min(max(percent, 0), 100)
}

private func tickDelta(from previousTick: integer_t, to tick: integer_t) -> UInt64 {
    let delta = tick - previousTick

    guard delta > 0 else {
        return 0
    }

    return UInt64(delta)
}

private func readLiveRamUsagePercent() -> Int {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &stats) { statsPointer in
        statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
            host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
        }
    }

    guard result == KERN_SUCCESS else {
        return 0
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
        return 0
    }

    return clampPercent(Int((Double(usedPages) / Double(totalPages) * 100).rounded()))
}

private func readLiveSsdUsagePercent() -> Int {
    do {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: dataVolumePath)
        let maybeFreeBytes = attributes[.systemFreeSize] as? NSNumber
        let maybeTotalBytes = attributes[.systemSize] as? NSNumber
        let freeBytes = maybeFreeBytes?.uint64Value ?? 0
        let totalBytes = maybeTotalBytes?.uint64Value ?? 0

        guard totalBytes > 0, totalBytes >= freeBytes else {
            return 0
        }

        return clampPercent(Int((Double(totalBytes - freeBytes) / Double(totalBytes) * 100).rounded()))
    } catch {
        return 0
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

private func readLiveNetworkCounters() -> NetworkCounters {
    var maybeInterfaces: UnsafeMutablePointer<ifaddrs>?
    var uploadBytes: UInt64 = 0
    var downloadBytes: UInt64 = 0
    let activeInterfaceNames = getActiveNetworkInterfaceNames()

    guard getifaddrs(&maybeInterfaces) == 0, let interfaces = maybeInterfaces else {
        return NetworkCounters(uploadBytes: 0, downloadBytes: 0)
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

import Foundation

public struct MetricsSnapshot: Equatable {
    public let cpuUsagePercent: Int
    public let ramUsagePercent: Int
    public let ssdUsagePercent: Int
    public let networkUploadBytesPerSecond: UInt64
    public let networkDownloadBytesPerSecond: UInt64

    public init(
        cpuUsagePercent: Int,
        ramUsagePercent: Int,
        ssdUsagePercent: Int,
        networkUploadBytesPerSecond: UInt64,
        networkDownloadBytesPerSecond: UInt64
    ) {
        self.cpuUsagePercent = cpuUsagePercent
        self.ramUsagePercent = ramUsagePercent
        self.ssdUsagePercent = ssdUsagePercent
        self.networkUploadBytesPerSecond = networkUploadBytesPerSecond
        self.networkDownloadBytesPerSecond = networkDownloadBytesPerSecond
    }
}

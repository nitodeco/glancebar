import Foundation

public struct MetricsSnapshot: Equatable, Sendable {
    public let cpuUsagePercent: Int?
    public let gpuUsagePercent: Int?
    public let ramUsagePercent: Int?
    public let ssdUsagePercent: Int?
    public let networkUploadBytesPerSecond: UInt64?
    public let networkDownloadBytesPerSecond: UInt64?

    public init(
        cpuUsagePercent: Int? = nil,
        gpuUsagePercent: Int? = nil,
        ramUsagePercent: Int? = nil,
        ssdUsagePercent: Int? = nil,
        networkUploadBytesPerSecond: UInt64? = nil,
        networkDownloadBytesPerSecond: UInt64? = nil
    ) {
        self.cpuUsagePercent = cpuUsagePercent
        self.gpuUsagePercent = gpuUsagePercent
        self.ramUsagePercent = ramUsagePercent
        self.ssdUsagePercent = ssdUsagePercent
        self.networkUploadBytesPerSecond = networkUploadBytesPerSecond
        self.networkDownloadBytesPerSecond = networkDownloadBytesPerSecond
    }
}

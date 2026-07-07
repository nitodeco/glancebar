import Foundation

private let bytesPerKilobyte = 1_000.0
private let bytesPerMegabyte = 1_000_000.0

public struct ThroughputFormat: Equatable {
    public let value: String
    public let unit: String
}

public enum ByteFormatter {
    public static func formatThroughputParts(bytesPerSecond: UInt64) -> ThroughputFormat {
        if Double(bytesPerSecond) >= bytesPerMegabyte {
            return ThroughputFormat(value: formatDecimal(value: Double(bytesPerSecond) / bytesPerMegabyte), unit: "MB/s")
        }

        return ThroughputFormat(value: formatDecimal(value: Double(bytesPerSecond) / bytesPerKilobyte), unit: "KB/s")
    }

    public static func formatThroughput(bytesPerSecond: UInt64) -> String {
        let throughputFormat = formatThroughputParts(bytesPerSecond: bytesPerSecond)

        return "\(throughputFormat.value) \(throughputFormat.unit)"
    }
}

private func formatDecimal(value: Double) -> String {
    String(format: "%.1f", value)
        .replacingOccurrences(of: ".0", with: "")
}

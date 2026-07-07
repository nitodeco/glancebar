import Foundation

private let bytesPerKilobyte = 1_000.0
private let bytesPerMegabyte = 1_000_000.0

public enum ByteFormatter {
    public static func formatThroughput(bytesPerSecond: UInt64) -> String {
        if Double(bytesPerSecond) >= bytesPerMegabyte {
            return "\(formatDecimal(value: Double(bytesPerSecond) / bytesPerMegabyte)) MB/s"
        }

        return "\(formatDecimal(value: Double(bytesPerSecond) / bytesPerKilobyte)) KB/s"
    }
}

private func formatDecimal(value: Double) -> String {
    String(format: "%.1f", value)
        .replacingOccurrences(of: ".0", with: "")
}

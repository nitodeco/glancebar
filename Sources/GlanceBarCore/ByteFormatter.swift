import Foundation

public enum ByteFormatter {
    public static func formatThroughput(bytesPerSecond: UInt64) -> String {
        if bytesPerSecond >= 1_000_000_000 {
            return String(format: "%.1f GB/s", Double(bytesPerSecond) / 1_000_000_000)
        }

        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", Double(bytesPerSecond) / 1_000_000)
        }

        if bytesPerSecond >= 1_000 {
            return "\(bytesPerSecond / 1_000) KB/s"
        }

        return "\(bytesPerSecond) B/s"
    }
}

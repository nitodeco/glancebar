import Testing
@testable import GlanceBarCore

@Test func formatsThroughput() {
    #expect(ByteFormatter.formatThroughput(bytesPerSecond: 0) == "0 B/s")
    #expect(ByteFormatter.formatThroughput(bytesPerSecond: 999) == "999 B/s")
    #expect(ByteFormatter.formatThroughput(bytesPerSecond: 1_000) == "1 KB/s")
    #expect(ByteFormatter.formatThroughput(bytesPerSecond: 42_000) == "42 KB/s")
    #expect(ByteFormatter.formatThroughput(bytesPerSecond: 4_200_000) == "4.2 MB/s")
    #expect(ByteFormatter.formatThroughput(bytesPerSecond: 1_200_000_000) == "1.2 GB/s")
}

import AppKit
import GlanceBarCore

private let ramColumnX: CGFloat = 36
private let ssdColumnX: CGFloat = 72
private let networkColumnX: CGFloat = 108
private let labelY: CGFloat = 12
private let valueY: CGFloat = 0
private let labelFontSize: CGFloat = 9
private let valueFontSize: CGFloat = 12
private let networkFontSize: CGFloat = 10
private let warningThresholdPercent = 80

final class StatusMetricsView: NSView {
    static let preferredSize = NSSize(width: 166, height: 24)

    var snapshot = MetricsSnapshot(
        cpuUsagePercent: 0,
        ramUsagePercent: 0,
        ssdUsagePercent: 0,
        networkUploadBytesPerSecond: 0,
        networkDownloadBytesPerSecond: 0
    ) {
        didSet {
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        Self.preferredSize
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawColumn(label: "CPU", value: "\(snapshot.cpuUsagePercent)%", percent: snapshot.cpuUsagePercent, x: 0)
        drawColumn(label: "RAM", value: "\(snapshot.ramUsagePercent)%", percent: snapshot.ramUsagePercent, x: ramColumnX)
        drawColumn(label: "SSD", value: "\(snapshot.ssdUsagePercent)%", percent: snapshot.ssdUsagePercent, x: ssdColumnX)
        drawNetwork(x: networkColumnX)
    }

    private func drawColumn(label: String, value: String, percent: Int, x: CGFloat) {
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: labelFontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: .medium),
            .foregroundColor: getValueColor(percent: percent)
        ]

        label.draw(at: NSPoint(x: x, y: labelY), withAttributes: labelAttributes)
        value.draw(at: NSPoint(x: x, y: valueY), withAttributes: valueAttributes)
    }

    private func drawNetwork(x: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: networkFontSize, weight: .medium)
        ]
        let upload = "↑ \(ByteFormatter.formatThroughput(bytesPerSecond: snapshot.networkUploadBytesPerSecond))"
        let download = "↓ \(ByteFormatter.formatThroughput(bytesPerSecond: snapshot.networkDownloadBytesPerSecond))"

        upload.draw(
            at: NSPoint(x: x, y: labelY),
            withAttributes: attributes.merging([.foregroundColor: NSColor.systemPurple]) { firstValue, _ in firstValue }
        )
        download.draw(
            at: NSPoint(x: x, y: valueY),
            withAttributes: attributes.merging([.foregroundColor: NSColor.systemBlue]) { firstValue, _ in firstValue }
        )
    }

    private func getValueColor(percent: Int) -> NSColor {
        if percent > warningThresholdPercent {
            return .systemRed
        }

        return .labelColor
    }
}

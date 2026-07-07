import AppKit
import GlanceBarCore

private let ramColumnX: CGFloat = 36
private let ssdColumnX: CGFloat = 72
private let networkColumnX: CGFloat = 102
private let enabledGpuColumnX: CGFloat = 36
private let enabledRamColumnX: CGFloat = 72
private let enabledSsdColumnX: CGFloat = 108
private let enabledNetworkColumnX: CGFloat = 138
private let labelY: CGFloat = 12
private let valueY: CGFloat = 0
private let labelFontSize: CGFloat = 9
private let valueFontSize: CGFloat = 12
private let networkFontSize: CGFloat = 10
private let networkValueWidth: CGFloat = 32
private let networkUnitXOffset: CGFloat = 36
private let contentHorizontalPadding: CGFloat = 12
private let backgroundHorizontalInset: CGFloat = 1
private let backgroundVerticalInset: CGFloat = 2

final class StatusMetricsView: NSView {
    static func preferredSize(configuration: AppConfiguration) -> NSSize {
        NSSize(width: (configuration.isGpuEnabled ? 196 : 160) + contentHorizontalPadding * 2, height: 24)
    }

    var configuration = makeDefaultAppConfiguration() {
        didSet {
            needsDisplay = true
        }
    }

    var snapshot = MetricsSnapshot(
        cpuUsagePercent: 0,
        gpuUsagePercent: nil,
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
        Self.preferredSize(configuration: configuration)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawBackground()
        NSGraphicsContext.saveGraphicsState()
        let contentTransform = NSAffineTransform()
        contentTransform.translateX(by: contentHorizontalPadding, yBy: 0)
        contentTransform.concat()
        drawColumn(label: "CPU", value: "\(snapshot.cpuUsagePercent)%", percent: snapshot.cpuUsagePercent, x: 0)

        if configuration.isGpuEnabled {
            let gpuUsagePercent = snapshot.gpuUsagePercent ?? 0
            drawColumn(label: "GPU", value: "\(gpuUsagePercent)%", percent: gpuUsagePercent, x: enabledGpuColumnX)
            drawColumn(label: "RAM", value: "\(snapshot.ramUsagePercent)%", percent: snapshot.ramUsagePercent, x: enabledRamColumnX)
            drawColumn(label: "SSD", value: "\(snapshot.ssdUsagePercent)%", percent: snapshot.ssdUsagePercent, x: enabledSsdColumnX)
            drawNetwork(x: enabledNetworkColumnX)
            NSGraphicsContext.restoreGraphicsState()

            return
        }

        drawColumn(label: "RAM", value: "\(snapshot.ramUsagePercent)%", percent: snapshot.ramUsagePercent, x: ramColumnX)
        drawColumn(label: "SSD", value: "\(snapshot.ssdUsagePercent)%", percent: snapshot.ssdUsagePercent, x: ssdColumnX)
        drawNetwork(x: networkColumnX)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBackground() {
        guard configuration.isBackgroundEnabled else {
            return
        }

        configuration.backgroundColor.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: backgroundHorizontalInset, dy: backgroundVerticalInset),
            xRadius: 5,
            yRadius: 5
        ).fill()
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
        let valueParagraphStyle = NSMutableParagraphStyle()
        valueParagraphStyle.alignment = .right
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: networkFontSize, weight: .medium),
            .paragraphStyle: valueParagraphStyle
        ]
        let unitAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: networkFontSize, weight: .medium)
        ]
        let upload = ByteFormatter.formatThroughputParts(bytesPerSecond: snapshot.networkUploadBytesPerSecond)
        let download = ByteFormatter.formatThroughputParts(bytesPerSecond: snapshot.networkDownloadBytesPerSecond)

        drawNetworkRow(
            throughputFormat: upload,
            x: x,
            y: labelY,
            color: configuration.uploadColor,
            valueAttributes: valueAttributes,
            unitAttributes: unitAttributes
        )
        drawNetworkRow(
            throughputFormat: download,
            x: x,
            y: valueY,
            color: configuration.downloadColor,
            valueAttributes: valueAttributes,
            unitAttributes: unitAttributes
        )
    }

    private func drawNetworkRow(
        throughputFormat: ThroughputFormat,
        x: CGFloat,
        y: CGFloat,
        color: NSColor,
        valueAttributes: [NSAttributedString.Key: Any],
        unitAttributes: [NSAttributedString.Key: Any]
    ) {
        throughputFormat.value.draw(
            in: NSRect(x: x, y: y, width: networkValueWidth, height: networkFontSize + 2),
            withAttributes: valueAttributes.merging([.foregroundColor: color]) { firstValue, _ in firstValue }
        )
        throughputFormat.unit.draw(
            at: NSPoint(x: x + networkUnitXOffset, y: y),
            withAttributes: unitAttributes.merging([.foregroundColor: color]) { firstValue, _ in firstValue }
        )
    }

    private func getValueColor(percent: Int) -> NSColor {
        if percent > configuration.warningThresholdPercent {
            return configuration.warningColor
        }

        if percent > configuration.yellowThresholdPercent {
            return configuration.yellowColor
        }

        return .labelColor
    }
}

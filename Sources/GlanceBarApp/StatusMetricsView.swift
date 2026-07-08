import AppKit
import GlanceBarCore

private let metricColumnWidth: CGFloat = 36
private let metricColumnSpacing: CGFloat = 0
private let networkColumnWidth: CGFloat = 58
private let labelY: CGFloat = 12
private let valueY: CGFloat = 2
private let labelFontSize: CGFloat = 8
private let valueFontSize: CGFloat = 11
private let networkFontSize: CGFloat = 9
private let networkValueWidth: CGFloat = 32
private let networkUnitXOffset: CGFloat = 36

final class StatusMetricsView: NSView {
    static func preferredSize(configuration: AppConfiguration) -> NSSize {
        NSSize(width: max(1, getEnabledMetrics(configuration: configuration).reduce(CGFloat(0)) { width, metricConfiguration in
            width + getMetricWidth(metricID: metricConfiguration.id) + metricColumnSpacing
        }), height: 24)
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

    var adaptiveTextColor: NSColor? {
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

        var metricX: CGFloat = 0

        for metricConfiguration in Self.getEnabledMetrics(configuration: configuration) {
            drawMetric(metricID: metricConfiguration.id, x: metricX)
            metricX += Self.getMetricWidth(metricID: metricConfiguration.id) + metricColumnSpacing
        }
    }

    private static func getEnabledMetrics(configuration: AppConfiguration) -> [MetricConfiguration] {
        configuration.orderedMetricIDs.compactMap { metricID in
            guard configuration.enabledMetricIDs.contains(metricID) else {
                return nil
            }

            return getMetricConfiguration(id: metricID)
        }
    }

    private static func getMetricWidth(metricID: String) -> CGFloat {
        if metricID == networkMetricID {
            return networkColumnWidth
        }

        return metricColumnWidth
    }

    private func drawMetric(metricID: String, x: CGFloat) {
        if metricID == cpuMetricID {
            drawColumn(label: "CPU", value: "\(snapshot.cpuUsagePercent)%", percent: snapshot.cpuUsagePercent, x: x)

            return
        }

        if metricID == gpuMetricID {
            let gpuUsagePercent = snapshot.gpuUsagePercent ?? 0
            drawColumn(label: "GPU", value: "\(gpuUsagePercent)%", percent: gpuUsagePercent, x: x)

            return
        }

        if metricID == ramMetricID {
            drawColumn(label: "RAM", value: "\(snapshot.ramUsagePercent)%", percent: snapshot.ramUsagePercent, x: x)

            return
        }

        if metricID == ssdMetricID {
            drawColumn(label: "SSD", value: "\(snapshot.ssdUsagePercent)%", percent: snapshot.ssdUsagePercent, x: x)

            return
        }

        drawNetwork(x: x)
    }

    private func drawColumn(label: String, value: String, percent: Int, x: CGFloat) {
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: labelFontSize, weight: .regular),
            .foregroundColor: adaptiveTextColor ?? configuration.labelTextColor
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

        return adaptiveTextColor ?? configuration.baseTextColor
    }
}

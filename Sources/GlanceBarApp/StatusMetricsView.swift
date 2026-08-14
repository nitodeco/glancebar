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

    var snapshot = MetricsSnapshot() {
        didSet {
            needsDisplay = true
        }
    }

    var adaptiveColorsByRoleID: [String: NSColor] = [:] {
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
            drawColumn(label: "CPU", percent: snapshot.cpuUsagePercent, x: x)

            return
        }

        if metricID == gpuMetricID {
            drawColumn(label: "GPU", percent: snapshot.gpuUsagePercent, x: x)

            return
        }

        if metricID == ramMetricID {
            drawColumn(label: "RAM", percent: snapshot.ramUsagePercent, x: x)

            return
        }

        if metricID == ssdMetricID {
            drawColumn(label: "SSD", percent: snapshot.ssdUsagePercent, x: x)

            return
        }

        drawNetwork(x: x)
    }

    private func drawColumn(label: String, percent: Int?, x: CGFloat) {
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: getLabelFont(),
            .foregroundColor: getDrawableColor(
                adaptiveColorsByRoleID[labelTextColorKey] ?? configuration.labelTextColor
            )
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: getValueFont(),
            .foregroundColor: getDrawableColor(
                percent.map(getValueColor)
                    ?? adaptiveColorsByRoleID[baseTextColorKey]
                    ?? configuration.baseTextColor
            )
        ]

        label.draw(at: NSPoint(x: x, y: labelY), withAttributes: labelAttributes)
        formatPercentage(percent).draw(at: NSPoint(x: x, y: valueY), withAttributes: valueAttributes)
    }

    private func drawNetwork(x: CGFloat) {
        let valueParagraphStyle = NSMutableParagraphStyle()
        valueParagraphStyle.alignment = .right
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: getNetworkFont(),
            .paragraphStyle: valueParagraphStyle
        ]
        let unitAttributes: [NSAttributedString.Key: Any] = [
            .font: getNetworkFont()
        ]
        drawNetworkValue(
            maybeBytesPerSecond: snapshot.networkUploadBytesPerSecond,
            x: x,
            y: labelY,
            color: adaptiveColorsByRoleID[uploadColorKey] ?? configuration.uploadColor,
            valueAttributes: valueAttributes,
            unitAttributes: unitAttributes
        )
        drawNetworkValue(
            maybeBytesPerSecond: snapshot.networkDownloadBytesPerSecond,
            x: x,
            y: valueY,
            color: adaptiveColorsByRoleID[downloadColorKey] ?? configuration.downloadColor,
            valueAttributes: valueAttributes,
            unitAttributes: unitAttributes
        )
    }

    private func drawNetworkValue(
        maybeBytesPerSecond: UInt64?,
        x: CGFloat,
        y: CGFloat,
        color: NSColor,
        valueAttributes: [NSAttributedString.Key: Any],
        unitAttributes: [NSAttributedString.Key: Any]
    ) {
        guard let bytesPerSecond = maybeBytesPerSecond else {
            "-".draw(
                in: NSRect(x: x, y: y, width: networkValueWidth, height: networkFontSize + 2),
                withAttributes: valueAttributes.merging([.foregroundColor: getDrawableColor(color)]) { firstValue, _ in firstValue }
            )
            return
        }

        drawNetworkRow(
            throughputFormat: ByteFormatter.formatThroughputParts(bytesPerSecond: bytesPerSecond),
            x: x,
            y: y,
            color: color,
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
            withAttributes: valueAttributes.merging([.foregroundColor: getDrawableColor(color)]) { firstValue, _ in firstValue }
        )
        throughputFormat.unit.draw(
            at: NSPoint(x: x + networkUnitXOffset, y: y),
            withAttributes: unitAttributes.merging([.foregroundColor: getDrawableColor(color)]) { firstValue, _ in firstValue }
        )
    }

    private func getValueColor(percent: Int) -> NSColor {
        if percent > configuration.criticalThresholdPercent {
            return adaptiveColorsByRoleID[criticalColorKey] ?? configuration.criticalColor
        }

        if percent > configuration.warningThresholdPercent {
            return adaptiveColorsByRoleID[warningColorKey] ?? configuration.warningColor
        }

        return adaptiveColorsByRoleID[baseTextColorKey] ?? configuration.baseTextColor
    }

    private func getDrawableColor(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? .labelColor
    }

    private func getLabelFont() -> NSFont {
        NSFont(name: "Menlo", size: labelFontSize) ?? NSFont.systemFont(ofSize: labelFontSize, weight: .regular)
    }

    private func getValueFont() -> NSFont {
        NSFont(name: "Menlo", size: valueFontSize) ?? NSFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: .medium)
    }

    private func getNetworkFont() -> NSFont {
        NSFont(name: "Menlo", size: networkFontSize) ?? NSFont.monospacedDigitSystemFont(ofSize: networkFontSize, weight: .medium)
    }
}

func formatPercentage(_ percent: Int?) -> String {
    percent.map { "\($0)%" } ?? "-"
}

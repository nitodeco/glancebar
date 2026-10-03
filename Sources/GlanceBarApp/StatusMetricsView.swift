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

private struct RenderedMetricColumn: Equatable {
    let metricID: String
    let rect: NSRect
    let values: [String]
    let colors: [NSColor]
}

class StatusMetricsView: NSView {
    private var renderedColumns: [RenderedMetricColumn] = []
    private lazy var labelFont = getLabelFont()
    private lazy var valueFont = getValueFont()
    private lazy var networkFont = getNetworkFont()
    private lazy var networkParagraphStyle: NSParagraphStyle = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        return paragraphStyle
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        updateRenderedColumns()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    static func preferredSize(configuration: AppConfiguration) -> NSSize {
        NSSize(width: max(1, getEnabledMetrics(configuration: configuration).reduce(CGFloat(0)) { width, metricConfiguration in
            width + getMetricWidth(metricID: metricConfiguration.id) + metricColumnSpacing
        }), height: 24)
    }

    var configuration = makeDefaultAppConfiguration() {
        didSet {
            updateRenderedColumns()
        }
    }

    var snapshot = MetricsSnapshot() {
        didSet {
            if snapshot != oldValue {
                updateRenderedColumns()
            }
        }
    }

    var adaptiveColorsByRoleID: [String: NSColor] = [:] {
        didSet {
            if adaptiveColorsByRoleID != oldValue {
                updateRenderedColumns()
            }
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

        for column in renderedColumns where needsToDraw(column.rect) {
            drawMetric(metricID: column.metricID, x: column.rect.minX)
        }
    }

    private func updateRenderedColumns() {
        let previousColumns = renderedColumns
        var metricX: CGFloat = 0
        var updatedColumns: [RenderedMetricColumn] = []

        for metricConfiguration in Self.getEnabledMetrics(configuration: configuration) {
            let metricID = metricConfiguration.id
            let columnRect = NSRect(x: metricX, y: 0, width: Self.getMetricWidth(metricID: metricID), height: 24)
            let column = getRenderedColumn(metricID: metricID, rect: columnRect)
            updatedColumns.append(column)

            if !previousColumns.contains(column) {
                setNeedsDisplay(columnRect)
            }

            metricX += columnRect.width + metricColumnSpacing
        }

        for previousColumn in previousColumns {
            if !updatedColumns.contains(where: { $0.rect == previousColumn.rect }) {
                setNeedsDisplay(previousColumn.rect)
            }
        }

        renderedColumns = updatedColumns
    }

    private func getRenderedColumn(metricID: String, rect: NSRect) -> RenderedMetricColumn {
        if metricID == networkMetricID {
            return RenderedMetricColumn(
                metricID: metricID,
                rect: rect,
                values: [
                    snapshot.networkUploadBytesPerSecond.map { ByteFormatter.formatThroughput(bytesPerSecond: $0) } ?? "-",
                    snapshot.networkDownloadBytesPerSecond.map { ByteFormatter.formatThroughput(bytesPerSecond: $0) } ?? "-"
                ],
                colors: [
                    getDrawableColor(adaptiveColorsByRoleID[uploadColorKey] ?? configuration.uploadColor),
                    getDrawableColor(adaptiveColorsByRoleID[downloadColorKey] ?? configuration.downloadColor)
                ]
            )
        }

        let maybePercent: Int?

        if metricID == cpuMetricID {
            maybePercent = snapshot.cpuUsagePercent
        } else if metricID == gpuMetricID {
            maybePercent = snapshot.gpuUsagePercent
        } else if metricID == ramMetricID {
            maybePercent = snapshot.ramUsagePercent
        } else {
            maybePercent = snapshot.ssdUsagePercent
        }

        return RenderedMetricColumn(
            metricID: metricID,
            rect: rect,
            values: [formatPercentage(maybePercent)],
            colors: [
                getDrawableColor(adaptiveColorsByRoleID[labelTextColorKey] ?? configuration.labelTextColor),
                getDrawableColor(maybePercent.map(getValueColor) ?? adaptiveColorsByRoleID[baseTextColorKey] ?? configuration.baseTextColor)
            ]
        )
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
            .font: labelFont,
            .foregroundColor: getDrawableColor(
                adaptiveColorsByRoleID[labelTextColorKey] ?? configuration.labelTextColor
            )
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: valueFont,
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
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: networkFont,
            .paragraphStyle: networkParagraphStyle
        ]
        let unitAttributes: [NSAttributedString.Key: Any] = [
            .font: networkFont
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

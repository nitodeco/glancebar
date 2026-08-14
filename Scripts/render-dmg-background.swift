import AppKit
import Foundation

private let canvasWidthInPixels = 660
private let canvasHeightInPixels = 390
private let gridSpacingInPixels: CGFloat = 30
private let arrowStart = CGPoint(x: 270, y: 195)
private let arrowEnd = CGPoint(x: 390, y: 195)
private let arrowHeadLengthInPixels: CGFloat = 18
private let arrowHeadHeightInPixels: CGFloat = 13
private let glanceBarLabelPlate = NSRect(x: 123, y: 98, width: 104, height: 27)
private let brandColors = [
    NSColor(srgbRed: 0.83, green: 0.62, blue: 0.00, alpha: 1),
    NSColor(srgbRed: 0.86, green: 0.04, blue: 0.08, alpha: 1),
    NSColor(srgbRed: 0.57, green: 0.19, blue: 0.94, alpha: 1),
    NSColor(srgbRed: 0.00, green: 0.31, blue: 0.97, alpha: 1)
]

private func drawGradientStroke(
    context: CGContext,
    path: CGPath,
    lineWidthInPixels: CGFloat,
    alpha: CGFloat,
    gradientStartXInPixels: CGFloat,
    gradientEndXInPixels: CGFloat
) {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let colors = brandColors.map { color in
        color.withAlphaComponent(alpha).cgColor
    } as CFArray
    let locations: [CGFloat] = [0, 0.33, 0.66, 1]

    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
        return
    }

    context.saveGState()
    context.addPath(path)
    context.setLineWidth(lineWidthInPixels)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: gradientStartXInPixels, y: 0),
        end: CGPoint(x: gradientEndXInPixels, y: 0),
        options: []
    )
    context.restoreGState()
}

private func drawGrid() {
    NSColor(srgbRed: 0.22, green: 0.23, blue: 0.25, alpha: 0.32).setStroke()

    for xPositionInPixels in stride(from: gridSpacingInPixels, to: CGFloat(canvasWidthInPixels), by: gridSpacingInPixels) {
        let gridLine = NSBezierPath()
        gridLine.move(to: CGPoint(x: xPositionInPixels, y: 0))
        gridLine.line(to: CGPoint(x: xPositionInPixels, y: CGFloat(canvasHeightInPixels)))
        gridLine.lineWidth = 0.5
        gridLine.stroke()
    }

    for yPositionInPixels in stride(from: gridSpacingInPixels, to: CGFloat(canvasHeightInPixels), by: gridSpacingInPixels) {
        let gridLine = NSBezierPath()
        gridLine.move(to: CGPoint(x: 0, y: yPositionInPixels))
        gridLine.line(to: CGPoint(x: CGFloat(canvasWidthInPixels), y: yPositionInPixels))
        gridLine.lineWidth = 0.5
        gridLine.stroke()
    }
}

private func makeActivityTracePath() -> CGPath {
    let tracePath = CGMutablePath()
    tracePath.move(to: CGPoint(x: 0, y: 28))
    tracePath.addCurve(to: CGPoint(x: 48, y: 70), control1: CGPoint(x: 18, y: 33), control2: CGPoint(x: 38, y: 40))
    tracePath.addCurve(to: CGPoint(x: 92, y: 25), control1: CGPoint(x: 58, y: 58), control2: CGPoint(x: 69, y: 31))
    tracePath.addCurve(to: CGPoint(x: 165, y: 22), control1: CGPoint(x: 120, y: 18), control2: CGPoint(x: 143, y: 20))
    tracePath.addCurve(to: CGPoint(x: 245, y: 55), control1: CGPoint(x: 204, y: 25), control2: CGPoint(x: 226, y: 28))
    tracePath.addCurve(to: CGPoint(x: 285, y: 20), control1: CGPoint(x: 254, y: 45), control2: CGPoint(x: 263, y: 24))
    tracePath.addCurve(to: CGPoint(x: 405, y: 18), control1: CGPoint(x: 330, y: 15), control2: CGPoint(x: 365, y: 23))
    tracePath.addCurve(to: CGPoint(x: 540, y: 22), control1: CGPoint(x: 450, y: 23), control2: CGPoint(x: 495, y: 17))
    tracePath.addCurve(to: CGPoint(x: 660, y: 50), control1: CGPoint(x: 585, y: 24), control2: CGPoint(x: 628, y: 31))

    return tracePath
}

private func makeArrowPath() -> CGPath {
    let arrowPath = CGMutablePath()
    arrowPath.move(to: arrowStart)
    arrowPath.addLine(to: arrowEnd)
    arrowPath.move(to: CGPoint(x: arrowEnd.x - arrowHeadLengthInPixels, y: arrowEnd.y + arrowHeadHeightInPixels))
    arrowPath.addLine(to: arrowEnd)
    arrowPath.addLine(to: CGPoint(x: arrowEnd.x - arrowHeadLengthInPixels, y: arrowEnd.y - arrowHeadHeightInPixels))

    return arrowPath
}

private func drawArrow(context: CGContext) {
    context.saveGState()
    context.addPath(makeArrowPath())
    context.setLineWidth(5)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(NSColor.white.cgColor)
    context.strokePath()
    context.restoreGState()
}

guard let outputPath = CommandLine.arguments.dropFirst().first else {
    fputs("An output PNG path is required.\n", stderr)
    exit(1)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasWidthInPixels,
    pixelsHigh: canvasHeightInPixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create the DMG background canvas.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
NSColor(srgbRed: 0.08, green: 0.09, blue: 0.10, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: canvasWidthInPixels, height: canvasHeightInPixels).fill()
drawGrid()
NSColor.white.withAlphaComponent(0.96).setFill()
NSBezierPath(roundedRect: glanceBarLabelPlate, xRadius: 7, yRadius: 7).fill()
drawGradientStroke(
    context: graphicsContext.cgContext,
    path: makeActivityTracePath(),
    lineWidthInPixels: 2.2,
    alpha: 0.22,
    gradientStartXInPixels: 0,
    gradientEndXInPixels: CGFloat(canvasWidthInPixels)
)
drawArrow(context: graphicsContext.cgContext)
graphicsContext.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode the DMG background.\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
} catch {
    fputs("Unable to write the DMG background: \(error.localizedDescription)\n", stderr)
    exit(1)
}

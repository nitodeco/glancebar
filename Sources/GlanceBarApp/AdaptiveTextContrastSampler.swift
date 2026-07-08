import AppKit
import CoreGraphics

private let adaptiveContrastMinimumSampleIntervalInSeconds: TimeInterval = 5
private let adaptiveContrastLuminanceThreshold = 0.56
private let adaptiveContrastDarkTextColor = NSColor(srgbRed: 0.03, green: 0.03, blue: 0.035, alpha: 1)
private let adaptiveContrastLightTextColor = NSColor.white
private let adaptiveContrastMaxColorByte = 255.0

@MainActor
final class AdaptiveTextContrastSampler {
    private var lastSampleDate = Date.distantPast
    private var cachedTextColor: NSColor?

    func reset() {
        lastSampleDate = .distantPast
        cachedTextColor = nil
    }

    func sampleTextColor(statusButton: NSStatusBarButton?, force: Bool = false) -> NSColor? {
        let now = Date()

        if !force, now.timeIntervalSince(lastSampleDate) < adaptiveContrastMinimumSampleIntervalInSeconds {
            return cachedTextColor
        }

        lastSampleDate = now

        guard let statusButton, let window = statusButton.window, let screen = window.screen else {
            cachedTextColor = nil
            return nil
        }

        let screenRect = window.convertToScreen(statusButton.bounds)
        let captureRect = CGRect(
            x: screenRect.minX,
            y: screen.frame.maxY - screenRect.maxY,
            width: max(1, screenRect.width),
            height: max(1, screenRect.height)
        ).integral

        let isCaptureRectUsable = captureRect.minX.isFinite
            && captureRect.minY.isFinite
            && captureRect.width.isFinite
            && captureRect.height.isFinite
            && captureRect.width > 0
            && captureRect.height > 0

        guard isCaptureRectUsable, let windowID = CGWindowID(exactly: window.windowNumber) else {
            cachedTextColor = nil
            return nil
        }

        guard let image = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenBelowWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            cachedTextColor = nil
            return nil
        }

        cachedTextColor = getTextColor(image: image)
        return cachedTextColor
    }

    private func getTextColor(image: CGImage) -> NSColor? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        let hasSampledPixel = pixel.withUnsafeMutableBytes { pixelBytes in
            guard let maybeContext = CGContext(
                data: pixelBytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            maybeContext.interpolationQuality = .low
            maybeContext.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))

            return true
        }

        guard hasSampledPixel else {
            return nil
        }

        var pixelIterator = pixel.makeIterator()
        let redByte = pixelIterator.next() ?? 0
        let greenByte = pixelIterator.next() ?? 0
        let blueByte = pixelIterator.next() ?? 0
        let red = Double(redByte) / adaptiveContrastMaxColorByte
        let green = Double(greenByte) / adaptiveContrastMaxColorByte
        let blue = Double(blueByte) / adaptiveContrastMaxColorByte
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

        if luminance > adaptiveContrastLuminanceThreshold {
            return adaptiveContrastDarkTextColor
        }

        return adaptiveContrastLightTextColor
    }
}

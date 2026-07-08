import AppKit
import CoreGraphics

private let adaptiveContrastMinimumSampleIntervalInSeconds: TimeInterval = 5
private let adaptiveContrastLuminanceThreshold = 0.56
private let adaptiveContrastDarkTextColor = NSColor(srgbRed: 0.03, green: 0.03, blue: 0.035, alpha: 1)
private let adaptiveContrastLightTextColor = NSColor.white
private let adaptiveContrastMaxColorByte = 255.0
private let adaptiveContrastSampleGutterWidthInPoints: CGFloat = 18
private let adaptiveContrastMinimumWallpaperCropSizeInPixels = 1.0

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

        if let appearanceTextColor = getAppearanceTextColor(statusButton: statusButton) {
            cachedTextColor = appearanceTextColor
            return cachedTextColor
        }

        let statusItemRect = window.convertToScreen(statusButton.bounds)
        if let wallpaperTextColor = getWallpaperTextColor(statusItemRect: statusItemRect, screen: screen) {
            cachedTextColor = wallpaperTextColor
            return cachedTextColor
        }

        guard let displayIDNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            cachedTextColor = nil
            return nil
        }

        guard CGPreflightScreenCaptureAccess() else {
            cachedTextColor = nil
            return nil
        }

        let sampleRects = getSampleRects(statusItemRect: statusItemRect, screen: screen)
            .compactMap { sampleRect in
                getDisplayPixelRect(sampleRect: sampleRect, screen: screen)
            }

        guard !sampleRects.isEmpty else {
            cachedTextColor = nil
            return nil
        }

        let samples = sampleRects.compactMap { sampleRect in
            CGDisplayCreateImage(CGDirectDisplayID(displayIDNumber.uint32Value), rect: sampleRect)
        }

        cachedTextColor = getTextColor(images: samples)
        return cachedTextColor
    }

    private func getAppearanceTextColor(statusButton: NSStatusBarButton) -> NSColor? {
        let appearanceName = statusButton.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])

        if appearanceName == .darkAqua {
            return adaptiveContrastLightTextColor
        }

        if appearanceName == .aqua {
            return adaptiveContrastDarkTextColor
        }

        return nil
    }

    private func getSampleRects(statusItemRect: CGRect, screen: NSScreen) -> [CGRect] {
        let leftWidth = min(adaptiveContrastSampleGutterWidthInPoints, statusItemRect.minX - screen.frame.minX)
        let rightWidth = min(adaptiveContrastSampleGutterWidthInPoints, screen.frame.maxX - statusItemRect.maxX)
        let leftRect = CGRect(
            x: statusItemRect.minX - leftWidth,
            y: statusItemRect.minY,
            width: leftWidth,
            height: statusItemRect.height
        )
        let rightRect = CGRect(
            x: statusItemRect.maxX,
            y: statusItemRect.minY,
            width: rightWidth,
            height: statusItemRect.height
        )
        let fallbackRect = CGRect(
            x: statusItemRect.minX,
            y: statusItemRect.minY,
            width: min(adaptiveContrastSampleGutterWidthInPoints, statusItemRect.width),
            height: statusItemRect.height
        )
        let sampleRects = [leftRect, rightRect].filter { sampleRect in
            sampleRect.width > 0 && sampleRect.height > 0
        }

        if sampleRects.isEmpty {
            return [fallbackRect]
        }

        return sampleRects
    }

    private func getDisplayPixelRect(sampleRect: CGRect, screen: NSScreen) -> CGRect? {
        let backingScaleFactor = screen.backingScaleFactor
        let displayRect = CGRect(
            x: (sampleRect.minX - screen.frame.minX) * backingScaleFactor,
            y: (screen.frame.maxY - sampleRect.maxY) * backingScaleFactor,
            width: sampleRect.width * backingScaleFactor,
            height: sampleRect.height * backingScaleFactor
        ).integral
        let isDisplayRectUsable = displayRect.minX.isFinite
            && displayRect.minY.isFinite
            && displayRect.width.isFinite
            && displayRect.height.isFinite
            && displayRect.width > 0
            && displayRect.height > 0

        if !isDisplayRectUsable {
            return nil
        }

        return displayRect
    }

    private func getWallpaperTextColor(statusItemRect: CGRect, screen: NSScreen) -> NSColor? {
        guard let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen),
              let wallpaperImage = NSImage(contentsOf: wallpaperURL),
              let wallpaperCGImage = wallpaperImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }

        let wallpaperSize = CGSize(width: wallpaperCGImage.width, height: wallpaperCGImage.height)
        let wallpaperScale = max(screen.frame.width / wallpaperSize.width, screen.frame.height / wallpaperSize.height)
        let displayedWallpaperSize = CGSize(
            width: wallpaperSize.width * wallpaperScale,
            height: wallpaperSize.height * wallpaperScale
        )
        let hiddenWallpaperWidthInPixels = max(0, displayedWallpaperSize.width - screen.frame.width) / (2 * wallpaperScale)
        let hiddenWallpaperHeightInPixels = max(0, displayedWallpaperSize.height - screen.frame.height) / (2 * wallpaperScale)
        let statusItemRectFromTop = CGRect(
            x: statusItemRect.minX - screen.frame.minX,
            y: screen.frame.maxY - statusItemRect.maxY,
            width: statusItemRect.width,
            height: statusItemRect.height
        )
        let wallpaperCropRect = CGRect(
            x: hiddenWallpaperWidthInPixels + statusItemRectFromTop.minX / wallpaperScale,
            y: hiddenWallpaperHeightInPixels + statusItemRectFromTop.minY / wallpaperScale,
            width: statusItemRectFromTop.width / wallpaperScale,
            height: statusItemRectFromTop.height / wallpaperScale
        ).integral
        let usableWallpaperRect = wallpaperCropRect.intersection(CGRect(origin: .zero, size: wallpaperSize))

        guard usableWallpaperRect.width >= adaptiveContrastMinimumWallpaperCropSizeInPixels,
              usableWallpaperRect.height >= adaptiveContrastMinimumWallpaperCropSizeInPixels,
              let wallpaperCrop = wallpaperCGImage.cropping(to: usableWallpaperRect)
        else {
            return nil
        }

        return getTextColor(images: [wallpaperCrop])
    }

    private func getTextColor(images: [CGImage]) -> NSColor? {
        let pixels = images.compactMap { image in
            getAveragePixel(image: image)
        }

        guard !pixels.isEmpty else {
            return nil
        }

        let initialColorTotals: (red: Double, green: Double, blue: Double) = (red: 0, green: 0, blue: 0)
        let colorTotals = pixels.reduce(initialColorTotals) { colorTotals, pixel in
            (
                red: colorTotals.red + pixel.red,
                green: colorTotals.green + pixel.green,
                blue: colorTotals.blue + pixel.blue
            )
        }
        let sampleCount = Double(pixels.count)
        let red = colorTotals.red / sampleCount
        let green = colorTotals.green / sampleCount
        let blue = colorTotals.blue / sampleCount
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

        if luminance > adaptiveContrastLuminanceThreshold {
            return adaptiveContrastDarkTextColor
        }

        return adaptiveContrastLightTextColor
    }

    private func getAveragePixel(image: CGImage) -> (red: Double, green: Double, blue: Double)? {
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

        return (red: red, green: green, blue: blue)
    }
}

import AppKit
import CoreGraphics

private let adaptiveContrastMinimumSampleIntervalInSeconds: TimeInterval = 5
private let adaptiveContrastMaxColorByte = 255.0
private let adaptiveContrastSampleGutterWidthInPoints: CGFloat = 18
private let adaptiveContrastMinimumWallpaperCropSizeInPixels = 1.0
private let adaptiveContrastDarkAppearanceBackground = NSColor(
    srgbRed: 0.12,
    green: 0.12,
    blue: 0.13,
    alpha: 1
)
private let adaptiveContrastLightAppearanceBackground = NSColor(
    srgbRed: 0.92,
    green: 0.92,
    blue: 0.93,
    alpha: 1
)

@MainActor
final class AdaptiveTextContrastSampler {
    private var lastSampleDate = Date.distantPast
    private var cachedBackgroundColor: NSColor?

    func reset() {
        lastSampleDate = .distantPast
        cachedBackgroundColor = nil
    }

    func sampleBackgroundColor(statusButton: NSStatusBarButton?, force: Bool = false) -> NSColor? {
        let now = Date()

        if !force, now.timeIntervalSince(lastSampleDate) < adaptiveContrastMinimumSampleIntervalInSeconds {
            return cachedBackgroundColor
        }

        lastSampleDate = now

        guard let statusButton, let window = statusButton.window, let screen = window.screen else {
            cachedBackgroundColor = nil
            return nil
        }

        let statusItemRect = window.convertToScreen(statusButton.bounds)

        if let screenColor = getScreenColor(statusItemRect: statusItemRect, screen: screen) {
            cachedBackgroundColor = screenColor
            return screenColor
        }

        if let wallpaperColor = getWallpaperColor(statusItemRect: statusItemRect, screen: screen) {
            cachedBackgroundColor = wallpaperColor
            return wallpaperColor
        }

        cachedBackgroundColor = getAppearanceBackgroundColor(statusButton: statusButton)
        return cachedBackgroundColor
    }

    private func getScreenColor(statusItemRect: CGRect, screen: NSScreen) -> NSColor? {
        guard CGPreflightScreenCaptureAccess(),
              let displayIDNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let displayID = UInt32(exactly: displayIDNumber.int64Value)
        else {
            return nil
        }

        let images = getSampleRects(statusItemRect: statusItemRect, screen: screen)
            .compactMap { sampleRect in
                getDisplayPixelRect(sampleRect: sampleRect, screen: screen)
            }
            .compactMap { sampleRect in
                CGDisplayCreateImage(CGDirectDisplayID(displayID), rect: sampleRect)
            }

        return getAverageColor(images: images)
    }

    private func getAppearanceBackgroundColor(statusButton: NSStatusBarButton) -> NSColor {
        if statusButton.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return adaptiveContrastDarkAppearanceBackground
        }

        return adaptiveContrastLightAppearanceBackground
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

        return sampleRects.isEmpty ? [fallbackRect] : sampleRects
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

        return isDisplayRectUsable ? displayRect : nil
    }

    private func getWallpaperColor(statusItemRect: CGRect, screen: NSScreen) -> NSColor? {
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
        let hiddenWallpaperWidthInPixels = max(0, displayedWallpaperSize.width - screen.frame.width)
            / (2 * wallpaperScale)
        let hiddenWallpaperHeightInPixels = max(0, displayedWallpaperSize.height - screen.frame.height)
            / (2 * wallpaperScale)
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
        let isUsableWallpaperRectValid = usableWallpaperRect.minX.isFinite
            && usableWallpaperRect.minY.isFinite
            && usableWallpaperRect.width.isFinite
            && usableWallpaperRect.height.isFinite

        guard isUsableWallpaperRectValid,
              usableWallpaperRect.width >= adaptiveContrastMinimumWallpaperCropSizeInPixels,
              usableWallpaperRect.height >= adaptiveContrastMinimumWallpaperCropSizeInPixels,
              let wallpaperCrop = wallpaperCGImage.cropping(to: usableWallpaperRect)
        else {
            return nil
        }

        return getAverageColor(images: [wallpaperCrop])
    }

    private func getAverageColor(images: [CGImage]) -> NSColor? {
        let pixels = images.compactMap { image in
            getAveragePixel(image: image)
        }

        guard !pixels.isEmpty else {
            return nil
        }

        let colorTotals = pixels.reduce((red: 0.0, green: 0.0, blue: 0.0)) { colorTotals, pixel in
            (
                red: colorTotals.red + pixel.red,
                green: colorTotals.green + pixel.green,
                blue: colorTotals.blue + pixel.blue
            )
        }
        let sampleCount = Double(pixels.count)

        return NSColor(
            srgbRed: colorTotals.red / sampleCount,
            green: colorTotals.green / sampleCount,
            blue: colorTotals.blue / sampleCount,
            alpha: 1
        )
    }

    private func getAveragePixel(image: CGImage) -> (red: Double, green: Double, blue: Double)? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        let hasSampledPixel = pixel.withUnsafeMutableBytes { pixelBytes in
            guard let context = CGContext(
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

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))

            return true
        }

        guard hasSampledPixel else {
            return nil
        }

        var pixelIterator = pixel.makeIterator()

        return (
            red: Double(pixelIterator.next() ?? 0) / adaptiveContrastMaxColorByte,
            green: Double(pixelIterator.next() ?? 0) / adaptiveContrastMaxColorByte,
            blue: Double(pixelIterator.next() ?? 0) / adaptiveContrastMaxColorByte
        )
    }
}

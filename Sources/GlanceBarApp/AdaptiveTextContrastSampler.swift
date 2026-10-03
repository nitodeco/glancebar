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

struct WallpaperColorCacheKey: Equatable {
    let url: URL
    let fileNumber: UInt64
    let systemNumber: UInt64
    let modificationDate: Date
    let fileSizeInBytes: UInt64
    let statusItemRect: CGRect
    let screenFrame: CGRect
    let backingScaleFactor: CGFloat
    let displayID: UInt32
    let appearanceName: String?
}

@MainActor
struct WallpaperColorCache {
    private var maybeSample: (key: WallpaperColorCacheKey, color: NSColor)?

    mutating func reset() {
        maybeSample = nil
    }

    mutating func color(for maybeKey: WallpaperColorCacheKey?, loadColor: () -> NSColor?) -> NSColor? {
        if let maybeKey, let maybeSample, maybeSample.key == maybeKey {
            return maybeSample.color
        }

        maybeSample = nil
        let maybeColor = loadColor()

        if let maybeKey, let maybeColor {
            maybeSample = (key: maybeKey, color: maybeColor)
        }

        return maybeColor
    }
}

@MainActor
final class AdaptiveTextContrastSampler: NSObject {
    private var lastSampleDate = Date.distantPast
    private var cachedBackgroundColor: NSColor?
    private var wallpaperColorCache = WallpaperColorCache()

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(wallpaperContextDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func wallpaperContextDidChange() {
        reset()
    }

    func reset() {
        lastSampleDate = .distantPast
        cachedBackgroundColor = nil
        wallpaperColorCache.reset()
    }

    func sampleBackgroundColor(statusButton: NSStatusBarButton?, force: Bool = false) -> NSColor? {
        autoreleasepool {
            sampleBackgroundColorInPool(statusButton: statusButton, force: force)
        }
    }

    private func sampleBackgroundColorInPool(statusButton: NSStatusBarButton?, force: Bool) -> NSColor? {
        let now = Date()

        if force {
            wallpaperColorCache.reset()
        }

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

        if let wallpaperColor = getWallpaperColor(statusItemRect: statusItemRect, screen: screen, statusButton: statusButton) {
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

    private func getWallpaperColor(statusItemRect: CGRect, screen: NSScreen, statusButton: NSStatusBarButton) -> NSColor? {
        guard let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen) else {
            wallpaperColorCache.reset()

            return nil
        }

        let maybeCacheKey = getWallpaperColorCacheKey(
            url: wallpaperURL,
            statusItemRect: statusItemRect,
            screenFrame: screen.frame,
            backingScaleFactor: screen.backingScaleFactor,
            maybeDisplayID: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            appearanceName: statusButton.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue
        )

        return wallpaperColorCache.color(for: maybeCacheKey) {
            getWallpaperColorFromImage(url: wallpaperURL, statusItemRect: statusItemRect, screenFrame: screen.frame)
        }
    }

    private func getWallpaperColorFromImage(url: URL, statusItemRect: CGRect, screenFrame: CGRect) -> NSColor? {
        guard let wallpaperImage = NSImage(contentsOf: url),
              let wallpaperCGImage = wallpaperImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }

        let wallpaperSize = CGSize(width: wallpaperCGImage.width, height: wallpaperCGImage.height)
        let wallpaperScale = max(screenFrame.width / wallpaperSize.width, screenFrame.height / wallpaperSize.height)
        let displayedWallpaperSize = CGSize(
            width: wallpaperSize.width * wallpaperScale,
            height: wallpaperSize.height * wallpaperScale
        )
        let hiddenWallpaperWidthInPixels = max(0, displayedWallpaperSize.width - screenFrame.width)
            / (2 * wallpaperScale)
        let hiddenWallpaperHeightInPixels = max(0, displayedWallpaperSize.height - screenFrame.height)
            / (2 * wallpaperScale)
        let statusItemRectFromTop = CGRect(
            x: statusItemRect.minX - screenFrame.minX,
            y: screenFrame.maxY - statusItemRect.maxY,
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

func getWallpaperColorCacheKey(
    url: URL,
    statusItemRect: CGRect,
    screenFrame: CGRect,
    backingScaleFactor: CGFloat,
    maybeDisplayID: NSNumber?,
    appearanceName: String?
) -> WallpaperColorCacheKey? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let fileNumber = attributes[.systemFileNumber] as? NSNumber,
          let systemNumber = attributes[.systemNumber] as? NSNumber,
          let modificationDate = attributes[.modificationDate] as? Date,
          let fileSize = attributes[.size] as? NSNumber,
          let maybeDisplayID,
          let displayID = UInt32(exactly: maybeDisplayID.int64Value)
    else {
        return nil
    }

    return WallpaperColorCacheKey(
        url: url,
        fileNumber: fileNumber.uint64Value,
        systemNumber: systemNumber.uint64Value,
        modificationDate: modificationDate,
        fileSizeInBytes: fileSize.uint64Value,
        statusItemRect: statusItemRect,
        screenFrame: screenFrame,
        backingScaleFactor: backingScaleFactor,
        displayID: displayID,
        appearanceName: appearanceName
    )
}

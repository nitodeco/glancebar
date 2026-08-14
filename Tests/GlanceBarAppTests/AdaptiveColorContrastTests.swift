import AppKit
import Testing
@testable import GlanceBarApp

@Test func darkensColorAgainstBrightYellowBackground() throws {
    let sourceColor = NSColor(srgbRed: 0.83, green: 0.62, blue: 0, alpha: 1)
    let backgroundColor = NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)
    let adjustedColor = getContrastAdjustedColor(color: sourceColor, backgroundColor: backgroundColor)
    let adjustedRgbColor = try #require(adjustedColor.usingColorSpace(.sRGB))
    let sourceRgbColor = try #require(sourceColor.usingColorSpace(.sRGB))

    #expect(adjustedRgbColor.brightnessComponent < sourceRgbColor.brightnessComponent)
    #expect(try #require(getContrastRatio(foregroundColor: adjustedColor, backgroundColor: backgroundColor)) >= 4.5)
}

@Test func lightensColorAgainstDarkBlueBackground() throws {
    let sourceColor = NSColor(srgbRed: 0, green: 0.31, blue: 0.97, alpha: 1)
    let backgroundColor = NSColor(srgbRed: 0, green: 0.20, blue: 0.55, alpha: 1)
    let adjustedColor = getContrastAdjustedColor(color: sourceColor, backgroundColor: backgroundColor)
    let adjustedRgbColor = try #require(adjustedColor.usingColorSpace(.sRGB))
    let sourceRgbColor = try #require(sourceColor.usingColorSpace(.sRGB))

    #expect(adjustedRgbColor.brightnessComponent > sourceRgbColor.brightnessComponent)
    #expect(try #require(getContrastRatio(foregroundColor: adjustedColor, backgroundColor: backgroundColor)) >= 4.5)
}

@Test func leavesAlreadyReadableColorUnchanged() {
    let sourceColor = NSColor.white
    let backgroundColor = NSColor.black

    #expect(getContrastAdjustedColor(color: sourceColor, backgroundColor: backgroundColor) == sourceColor)
}

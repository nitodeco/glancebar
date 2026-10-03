import AppKit
import Testing
@testable import GlanceBarApp

@MainActor
@Test func colorSwatchesAvoidTemplateTinting() {
    for colorPreset in textColorPresets + colorPresets {
        let swatch = makeColorPresetSwatch(color: colorPreset.color)

        #expect(!swatch.isTemplate)
    }
}

@MainActor
@Test func blackAndWhiteSwatchesKeepTheirColors() throws {
    for color in [NSColor.black, NSColor.white] {
        let swatch = makeColorPresetSwatch(color: color)
        let imageRepresentation = try #require(swatch.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: imageRepresentation))
        let centerColor = try #require(
            bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)
        )
        let presetColor = try #require(color.usingColorSpace(.sRGB))

        #expect(!swatch.isTemplate)
        #expect(abs(centerColor.redComponent - presetColor.redComponent) < 0.01)
        #expect(abs(centerColor.greenComponent - presetColor.greenComponent) < 0.01)
        #expect(abs(centerColor.blueComponent - presetColor.blueComponent) < 0.01)
        #expect(centerColor.alphaComponent == 1)
    }
}

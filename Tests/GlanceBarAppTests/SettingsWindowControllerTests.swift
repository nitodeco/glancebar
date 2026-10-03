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

@MainActor
private final class ColorEditorTestOwner {
    var maybeController: ColorEditorWindowController?
    var maybeFrame: NSRect?
}

@MainActor
@Test func closedColorEditorReleasesWindowAndPreservesPosition() throws {
    _ = NSApplication.shared
    let owner = ColorEditorTestOwner()
    let configuration = makeDefaultAppConfiguration()
    let role = try #require(colorRoles.first)
    let frame = NSRect(x: 200, y: 200, width: 340, height: 260)
    weak var maybeReleasedController: ColorEditorWindowController?
    weak var maybeReleasedWindow: NSWindow?

    autoreleasepool {
        owner.maybeController = ColorEditorWindowController(
            configuration: configuration,
            colorRole: role,
            maybeWindowFrame: frame,
            onAdjustmentChange: { _, _ in },
            onClose: { [weak owner] windowFrame in
                owner?.maybeFrame = windowFrame
                owner?.maybeController = nil
            }
        )
        maybeReleasedController = owner.maybeController
        maybeReleasedWindow = owner.maybeController?.window
        owner.maybeController?.close()
    }

    #expect(owner.maybeController == nil)
    #expect(maybeReleasedController == nil)
    #expect(maybeReleasedWindow == nil)
    #expect(owner.maybeFrame == frame)

    let reopenedController = ColorEditorWindowController(
        configuration: configuration,
        colorRole: role,
        maybeWindowFrame: owner.maybeFrame,
        onAdjustmentChange: { _, _ in },
        onClose: { _ in }
    )
    #expect(reopenedController.window?.frame == frame)
}

import AppKit

private let minimumReadableContrastRatio = 4.5
private let lightnessSearchStep = 0.001

func getContrastAdjustedColor(
    color: NSColor,
    backgroundColor: NSColor,
    minimumContrastRatio: Double = minimumReadableContrastRatio
) -> NSColor {
    guard let sourceComponents = getRgbComponents(color: color),
          let backgroundComponents = getRgbComponents(color: backgroundColor)
    else {
        return color
    }

    if getContrastRatio(foreground: sourceComponents, background: backgroundComponents) >= minimumContrastRatio {
        return color
    }

    let hslColor = getContrastHslColor(
        red: sourceComponents.red,
        green: sourceComponents.green,
        blue: sourceComponents.blue
    )
    let maximumStepCount = Int(ceil(max(hslColor.lightness, 1 - hslColor.lightness) / lightnessSearchStep))

    for stepCount in 1...max(maximumStepCount, 1) {
        let lightnessChange = Double(stepCount) * lightnessSearchStep
        let darkerComponents = getContrastRgbColor(
            hue: hslColor.hue,
            saturation: hslColor.saturation,
            lightness: max(0, hslColor.lightness - lightnessChange)
        )
        let lighterComponents = getContrastRgbColor(
            hue: hslColor.hue,
            saturation: hslColor.saturation,
            lightness: min(1, hslColor.lightness + lightnessChange)
        )
        let darkerContrastRatio = getContrastRatio(
            foreground: darkerComponents,
            background: backgroundComponents
        )
        let lighterContrastRatio = getContrastRatio(
            foreground: lighterComponents,
            background: backgroundComponents
        )
        let isDarkerReadable = darkerContrastRatio >= minimumContrastRatio
        let isLighterReadable = lighterContrastRatio >= minimumContrastRatio

        if isDarkerReadable || isLighterReadable {
            let selectedComponents = isDarkerReadable && (!isLighterReadable || darkerContrastRatio >= lighterContrastRatio)
                ? darkerComponents
                : lighterComponents

            return makeContrastColor(components: selectedComponents, alpha: sourceComponents.alpha)
        }
    }

    let darkestComponents = getContrastRgbColor(
        hue: hslColor.hue,
        saturation: hslColor.saturation,
        lightness: 0
    )
    let lightestComponents = getContrastRgbColor(hue: hslColor.hue, saturation: hslColor.saturation, lightness: 1)
    let fallbackComponents = getContrastRatio(foreground: darkestComponents, background: backgroundComponents)
        >= getContrastRatio(foreground: lightestComponents, background: backgroundComponents)
        ? darkestComponents
        : lightestComponents

    return makeContrastColor(components: fallbackComponents, alpha: sourceComponents.alpha)
}

func getContrastRatio(foregroundColor: NSColor, backgroundColor: NSColor) -> Double? {
    guard let foregroundComponents = getRgbComponents(color: foregroundColor),
          let backgroundComponents = getRgbComponents(color: backgroundColor)
    else {
        return nil
    }

    return getContrastRatio(foreground: foregroundComponents, background: backgroundComponents)
}

private func getRgbComponents(color: NSColor) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
    guard let rgbColor = color.usingColorSpace(.sRGB) else {
        return nil
    }

    return (
        red: Double(rgbColor.redComponent),
        green: Double(rgbColor.greenComponent),
        blue: Double(rgbColor.blueComponent),
        alpha: Double(rgbColor.alphaComponent)
    )
}

private func getContrastRatio(
    foreground: (red: Double, green: Double, blue: Double, alpha: Double),
    background: (red: Double, green: Double, blue: Double, alpha: Double)
) -> Double {
    let foregroundLuminance = getRelativeLuminance(components: foreground)
    let backgroundLuminance = getRelativeLuminance(components: background)

    return (max(foregroundLuminance, backgroundLuminance) + 0.05)
        / (min(foregroundLuminance, backgroundLuminance) + 0.05)
}

private func makeContrastColor(
    components: (red: Double, green: Double, blue: Double, alpha: Double),
    alpha: Double
) -> NSColor {
    NSColor(
        srgbRed: components.red,
        green: components.green,
        blue: components.blue,
        alpha: alpha
    )
}

private func getRelativeLuminance(
    components: (red: Double, green: Double, blue: Double, alpha: Double)
) -> Double {
    0.2126 * getLinearColorComponent(components.red)
        + 0.7152 * getLinearColorComponent(components.green)
        + 0.0722 * getLinearColorComponent(components.blue)
}

private func getLinearColorComponent(_ component: Double) -> Double {
    if component <= 0.04045 {
        return component / 12.92
    }

    return pow((component + 0.055) / 1.055, 2.4)
}

private func getContrastHslColor(
    red: Double,
    green: Double,
    blue: Double
) -> (hue: Double, saturation: Double, lightness: Double) {
    let maximumValue = max(red, max(green, blue))
    let minimumValue = min(red, min(green, blue))
    let lightness = (maximumValue + minimumValue) / 2
    let delta = maximumValue - minimumValue

    guard delta != 0 else {
        return (0, 0, lightness)
    }

    let saturation = delta / (1 - abs(2 * lightness - 1))
    let hue: Double

    if maximumValue == red {
        hue = getWrappedContrastHue((green - blue) / delta / 6)
    } else if maximumValue == green {
        hue = ((blue - red) / delta + 2) / 6
    } else {
        hue = ((red - green) / delta + 4) / 6
    }

    return (hue, saturation, lightness)
}

private func getContrastRgbColor(
    hue: Double,
    saturation: Double,
    lightness: Double
) -> (red: Double, green: Double, blue: Double, alpha: Double) {
    let chroma = (1 - abs(2 * lightness - 1)) * saturation
    let hueSegment = hue * 6
    let secondaryComponent = chroma * (1 - abs(hueSegment.truncatingRemainder(dividingBy: 2) - 1))
    let matchComponent = lightness - chroma / 2
    let rgbPrimeColor: (red: Double, green: Double, blue: Double)

    if hueSegment < 1 {
        rgbPrimeColor = (chroma, secondaryComponent, 0)
    } else if hueSegment < 2 {
        rgbPrimeColor = (secondaryComponent, chroma, 0)
    } else if hueSegment < 3 {
        rgbPrimeColor = (0, chroma, secondaryComponent)
    } else if hueSegment < 4 {
        rgbPrimeColor = (0, secondaryComponent, chroma)
    } else if hueSegment < 5 {
        rgbPrimeColor = (secondaryComponent, 0, chroma)
    } else {
        rgbPrimeColor = (chroma, 0, secondaryComponent)
    }

    return (
        red: rgbPrimeColor.red + matchComponent,
        green: rgbPrimeColor.green + matchComponent,
        blue: rgbPrimeColor.blue + matchComponent,
        alpha: 1
    )
}

private func getWrappedContrastHue(_ hue: Double) -> Double {
    if hue < 0 {
        return hue + 1
    }

    if hue > 1 {
        return hue - 1
    }

    return hue
}

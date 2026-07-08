import AppKit

let minimumPollingIntervalInSeconds: TimeInterval = 1
let maximumPollingIntervalInSeconds: TimeInterval = 60
let minimumGpuPollingMultiplier = 1
let maximumGpuPollingMultiplier = 20
let minimumWarningThresholdPercent = 1
let maximumWarningThresholdPercent = 100
let minimumColorAdjustmentPercent = -100
let maximumColorAdjustmentPercent = 100
let cpuMetricID = "cpu"
let gpuMetricID = "gpu"
let ramMetricID = "ram"
let ssdMetricID = "ssd"
let networkMetricID = "network"
let availableMetrics = [
    MetricConfiguration(id: cpuMetricID, title: "CPU", shortLabel: "CPU"),
    MetricConfiguration(id: gpuMetricID, title: "GPU", shortLabel: "GPU"),
    MetricConfiguration(id: ramMetricID, title: "RAM", shortLabel: "RAM"),
    MetricConfiguration(id: ssdMetricID, title: "SSD", shortLabel: "SSD"),
    MetricConfiguration(id: networkMetricID, title: "Network", shortLabel: "NET")
]
let colorPresets = [
    ColorPreset(id: "red", title: "Red", color: NSColor(srgbRed: 0.86, green: 0.04, blue: 0.08, alpha: 1)),
    ColorPreset(id: "orange", title: "Orange", color: NSColor(srgbRed: 0.88, green: 0.28, blue: 0.00, alpha: 1)),
    ColorPreset(id: "yellow", title: "Yellow", color: NSColor(srgbRed: 0.72, green: 0.54, blue: 0.00, alpha: 1)),
    ColorPreset(id: "purple", title: "Purple", color: NSColor(srgbRed: 0.50, green: 0.12, blue: 0.88, alpha: 1)),
    ColorPreset(id: "blue", title: "Blue", color: NSColor(srgbRed: 0.00, green: 0.28, blue: 0.88, alpha: 1)),
    ColorPreset(id: "teal", title: "Teal", color: NSColor(srgbRed: 0.00, green: 0.56, blue: 0.62, alpha: 1)),
    ColorPreset(id: "green", title: "Green", color: NSColor(srgbRed: 0.00, green: 0.58, blue: 0.18, alpha: 1))
]
let textColorPresets = [
    ColorPreset(id: "white", title: "White", color: .white),
    ColorPreset(id: "light-gray", title: "Light gray", color: NSColor(srgbRed: 0.78, green: 0.80, blue: 0.84, alpha: 1)),
    ColorPreset(id: "dark-gray", title: "Dark gray", color: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1)),
    ColorPreset(id: "black", title: "Black", color: .black)
]

private let pollingIntervalKey = "pollingIntervalInSeconds"
private let isGpuEnabledKey = "isGpuEnabled"
private let enabledMetricIDsKey = "enabledMetricIDs"
private let orderedMetricIDsKey = "orderedMetricIDs"
private let gpuPollingMultiplierKey = "gpuPollingMultiplier"
private let legacyGpuPollingIntervalKey = "gpuPollingIntervalInSeconds"
private let yellowThresholdKey = "yellowThresholdPercent"
let yellowColorKey = "yellowColor"
private let warningThresholdKey = "warningThresholdPercent"
let warningColorKey = "warningColor"
let uploadColorKey = "uploadColor"
let downloadColorKey = "downloadColor"
let baseTextColorKey = "baseTextColor"
let labelTextColorKey = "labelTextColor"
private let isAutoTextContrastEnabledKey = "isAutoTextContrastEnabled"
private let isLaunchAtLoginEnabledKey = "isLaunchAtLoginEnabled"
private let hueAdjustmentKeySuffix = "HueAdjustment"
private let saturationAdjustmentKeySuffix = "SaturationAdjustment"
private let lightnessAdjustmentKeySuffix = "LightnessAdjustment"
private let defaultPollingIntervalInSeconds: TimeInterval = 3
private let defaultEnabledMetricIDs = [cpuMetricID, ramMetricID, ssdMetricID, networkMetricID]
private let defaultOrderedMetricIDs = [cpuMetricID, gpuMetricID, ramMetricID, ssdMetricID, networkMetricID]
private let defaultGpuPollingMultiplier = 2
private let defaultYellowThresholdPercent = 60
private let defaultYellowColorID = "yellow"
private let defaultWarningThresholdPercent = 80
private let defaultWarningColorID = "red"
private let defaultUploadColorID = "purple"
private let defaultDownloadColorID = "blue"
private let defaultBaseTextColorID = "white"
private let defaultLabelTextColorID = "white"
private let defaultIsAutoTextContrastEnabled = false
private let defaultIsLaunchAtLoginEnabled = true

struct AppConfiguration {
    let pollingIntervalInSeconds: TimeInterval
    let isLaunchAtLoginEnabled: Bool
    let isGpuEnabled: Bool
    let enabledMetricIDs: Set<String>
    let orderedMetricIDs: [String]
    let gpuPollingMultiplier: Int
    let yellowThresholdPercent: Int
    let yellowColorID: String
    let warningThresholdPercent: Int
    let warningColorID: String
    let uploadColorID: String
    let downloadColorID: String
    let baseTextColorID: String
    let labelTextColorID: String
    let isAutoTextContrastEnabled: Bool
    let colorAdjustments: [String: ColorAdjustment]
    let yellowColor: NSColor
    let warningColor: NSColor
    let uploadColor: NSColor
    let downloadColor: NSColor
    let baseTextColor: NSColor
    let labelTextColor: NSColor
}

struct ColorPreset {
    let id: String
    let title: String
    let color: NSColor
}

struct MetricConfiguration: Equatable {
    let id: String
    let title: String
    let shortLabel: String
}

struct ColorAdjustment: Equatable {
    let huePercent: Int
    let saturationPercent: Int
    let lightnessPercent: Int
}

struct ColorRole {
    let id: String
    let title: String
    let usesTextPresets: Bool
}

let colorRoles = [
    ColorRole(id: yellowColorKey, title: "Yellow", usesTextPresets: false),
    ColorRole(id: warningColorKey, title: "Over threshold", usesTextPresets: false),
    ColorRole(id: uploadColorKey, title: "Upload", usesTextPresets: false),
    ColorRole(id: downloadColorKey, title: "Download", usesTextPresets: false),
    ColorRole(id: baseTextColorKey, title: "Base text", usesTextPresets: true),
    ColorRole(id: labelTextColorKey, title: "Label text", usesTextPresets: true)
]

@MainActor
final class AppConfigurationStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AppConfiguration {
        let defaultConfiguration = makeDefaultAppConfiguration()
        let pollingIntervalInSeconds = clamp(
            value: userDefaults.double(forKey: pollingIntervalKey),
            fallback: defaultConfiguration.pollingIntervalInSeconds,
            minValue: minimumPollingIntervalInSeconds,
            maxValue: maximumPollingIntervalInSeconds
        )
        let gpuPollingMultiplier = readGpuPollingMultiplier(
            pollingIntervalInSeconds: pollingIntervalInSeconds,
            fallback: defaultConfiguration.gpuPollingMultiplier
        )
        let warningThresholdPercent = clamp(
            value: userDefaults.integer(forKey: warningThresholdKey),
            fallback: defaultConfiguration.warningThresholdPercent,
            minValue: minimumWarningThresholdPercent,
            maxValue: maximumWarningThresholdPercent
        )
        let yellowThresholdPercent = clamp(
            value: userDefaults.integer(forKey: yellowThresholdKey),
            fallback: defaultConfiguration.yellowThresholdPercent,
            minValue: minimumWarningThresholdPercent,
            maxValue: max(minimumWarningThresholdPercent, warningThresholdPercent - 1)
        )

        return AppConfiguration(
            pollingIntervalInSeconds: pollingIntervalInSeconds,
            isLaunchAtLoginEnabled: userDefaults.object(forKey: isLaunchAtLoginEnabledKey) as? Bool ?? defaultConfiguration.isLaunchAtLoginEnabled,
            enabledMetricIDs: readEnabledMetricIDs(defaultConfiguration: defaultConfiguration),
            orderedMetricIDs: readOrderedMetricIDs(defaultConfiguration: defaultConfiguration),
            gpuPollingMultiplier: gpuPollingMultiplier,
            yellowThresholdPercent: yellowThresholdPercent,
            yellowColorID: readColorID(forKey: yellowColorKey, fallback: defaultConfiguration.yellowColorID),
            warningThresholdPercent: warningThresholdPercent,
            warningColorID: readColorID(forKey: warningColorKey, fallback: defaultConfiguration.warningColorID),
            uploadColorID: readColorID(forKey: uploadColorKey, fallback: defaultConfiguration.uploadColorID),
            downloadColorID: readColorID(forKey: downloadColorKey, fallback: defaultConfiguration.downloadColorID),
            baseTextColorID: readTextColorID(forKey: baseTextColorKey, fallback: defaultConfiguration.baseTextColorID),
            labelTextColorID: readTextColorID(forKey: labelTextColorKey, fallback: defaultConfiguration.labelTextColorID),
            isAutoTextContrastEnabled: userDefaults.object(forKey: isAutoTextContrastEnabledKey) as? Bool ?? defaultConfiguration.isAutoTextContrastEnabled,
            colorAdjustments: readColorAdjustments()
        )
    }

    func save(_ configuration: AppConfiguration) {
        userDefaults.set(configuration.pollingIntervalInSeconds, forKey: pollingIntervalKey)
        userDefaults.set(configuration.isLaunchAtLoginEnabled, forKey: isLaunchAtLoginEnabledKey)
        userDefaults.set(configuration.isGpuEnabled, forKey: isGpuEnabledKey)
        userDefaults.set(Array(configuration.enabledMetricIDs), forKey: enabledMetricIDsKey)
        userDefaults.set(configuration.orderedMetricIDs, forKey: orderedMetricIDsKey)
        userDefaults.set(configuration.gpuPollingMultiplier, forKey: gpuPollingMultiplierKey)
        userDefaults.set(configuration.yellowThresholdPercent, forKey: yellowThresholdKey)
        userDefaults.set(configuration.yellowColorID, forKey: yellowColorKey)
        userDefaults.set(configuration.warningThresholdPercent, forKey: warningThresholdKey)
        userDefaults.set(configuration.warningColorID, forKey: warningColorKey)
        userDefaults.set(configuration.uploadColorID, forKey: uploadColorKey)
        userDefaults.set(configuration.downloadColorID, forKey: downloadColorKey)
        userDefaults.set(configuration.baseTextColorID, forKey: baseTextColorKey)
        userDefaults.set(configuration.labelTextColorID, forKey: labelTextColorKey)
        userDefaults.set(configuration.isAutoTextContrastEnabled, forKey: isAutoTextContrastEnabledKey)
        for colorRole in colorRoles {
            let colorAdjustment = getColorAdjustment(colorAdjustments: configuration.colorAdjustments, roleID: colorRole.id)
            userDefaults.set(colorAdjustment.huePercent, forKey: colorRole.id + hueAdjustmentKeySuffix)
            userDefaults.set(colorAdjustment.saturationPercent, forKey: colorRole.id + saturationAdjustmentKeySuffix)
            userDefaults.set(colorAdjustment.lightnessPercent, forKey: colorRole.id + lightnessAdjustmentKeySuffix)
        }
    }

    private func readColorID(forKey key: String, fallback: String) -> String {
        let maybeColorID = userDefaults.string(forKey: key)

        return getColorPreset(id: maybeColorID)?.id ?? fallback
    }

    private func readTextColorID(forKey key: String, fallback: String) -> String {
        let maybeColorID = userDefaults.string(forKey: key)

        return getTextColorPreset(id: maybeColorID)?.id ?? fallback
    }

    private func readEnabledMetricIDs(defaultConfiguration: AppConfiguration) -> Set<String> {
        guard let maybeEnabledMetricIDs = userDefaults.stringArray(forKey: enabledMetricIDsKey) else {
            var enabledMetricIDs = defaultConfiguration.enabledMetricIDs

            if userDefaults.object(forKey: isGpuEnabledKey) as? Bool ?? defaultConfiguration.isGpuEnabled {
                enabledMetricIDs.insert(gpuMetricID)
            }

            return enabledMetricIDs
        }

        let availableMetricIDs = Set(availableMetrics.map(\.id))
        let enabledMetricIDs = Set(maybeEnabledMetricIDs.filter { metricID in
            availableMetricIDs.contains(metricID)
        })

        return enabledMetricIDs
    }

    private func readOrderedMetricIDs(defaultConfiguration: AppConfiguration) -> [String] {
        guard let maybeOrderedMetricIDs = userDefaults.stringArray(forKey: orderedMetricIDsKey) else {
            return defaultConfiguration.orderedMetricIDs
        }

        return normalizeMetricOrder(metricIDs: maybeOrderedMetricIDs)
    }

    private func readColorAdjustments() -> [String: ColorAdjustment] {
        colorRoles.reduce(into: [String: ColorAdjustment]()) { colorAdjustments, colorRole in
            colorAdjustments[colorRole.id] = ColorAdjustment(
                huePercent: readColorAdjustmentValue(forKey: colorRole.id + hueAdjustmentKeySuffix),
                saturationPercent: readColorAdjustmentValue(forKey: colorRole.id + saturationAdjustmentKeySuffix),
                lightnessPercent: readColorAdjustmentValue(forKey: colorRole.id + lightnessAdjustmentKeySuffix)
            )
        }
    }

    private func readColorAdjustmentValue(forKey key: String) -> Int {
        guard userDefaults.object(forKey: key) != nil else {
            return 0
        }

        return clamp(
            value: userDefaults.integer(forKey: key),
            fallback: 0,
            minValue: minimumColorAdjustmentPercent,
            maxValue: maximumColorAdjustmentPercent
        )
    }

    private func readGpuPollingMultiplier(pollingIntervalInSeconds: TimeInterval, fallback: Int) -> Int {
        let maybeStoredMultiplier = userDefaults.object(forKey: gpuPollingMultiplierKey) as? Int

        if let maybeStoredMultiplier {
            return clamp(
                value: maybeStoredMultiplier,
                fallback: fallback,
                minValue: minimumGpuPollingMultiplier,
                maxValue: maximumGpuPollingMultiplier
            )
        }

        let legacyGpuPollingIntervalInSeconds = userDefaults.double(forKey: legacyGpuPollingIntervalKey)

        guard legacyGpuPollingIntervalInSeconds > 0, pollingIntervalInSeconds > 0 else {
            return fallback
        }

        return clamp(
            value: Int((legacyGpuPollingIntervalInSeconds / pollingIntervalInSeconds).rounded()),
            fallback: fallback,
            minValue: minimumGpuPollingMultiplier,
            maxValue: maximumGpuPollingMultiplier
        )
    }
}

func makeDefaultAppConfiguration() -> AppConfiguration {
    AppConfiguration(
        pollingIntervalInSeconds: defaultPollingIntervalInSeconds,
        isLaunchAtLoginEnabled: defaultIsLaunchAtLoginEnabled,
        enabledMetricIDs: Set(defaultEnabledMetricIDs),
        orderedMetricIDs: defaultOrderedMetricIDs,
        gpuPollingMultiplier: defaultGpuPollingMultiplier,
        yellowThresholdPercent: defaultYellowThresholdPercent,
        yellowColorID: defaultYellowColorID,
        warningThresholdPercent: defaultWarningThresholdPercent,
        warningColorID: defaultWarningColorID,
        uploadColorID: defaultUploadColorID,
        downloadColorID: defaultDownloadColorID,
        baseTextColorID: defaultBaseTextColorID,
        labelTextColorID: defaultLabelTextColorID,
        isAutoTextContrastEnabled: defaultIsAutoTextContrastEnabled,
        colorAdjustments: [:]
    )
}

func getColorPreset(id maybeColorID: String?) -> ColorPreset? {
    colorPresets.first { colorPreset in
        colorPreset.id == maybeColorID
    }
}

func getTextColorPreset(id maybeColorID: String?) -> ColorPreset? {
    textColorPresets.first { colorPreset in
        colorPreset.id == maybeColorID
    }
}

extension AppConfiguration {
    init(
        pollingIntervalInSeconds: TimeInterval,
        isLaunchAtLoginEnabled: Bool,
        enabledMetricIDs: Set<String>,
        orderedMetricIDs: [String],
        gpuPollingMultiplier: Int,
        yellowThresholdPercent: Int,
        yellowColorID: String,
        warningThresholdPercent: Int,
        warningColorID: String,
        uploadColorID: String,
        downloadColorID: String,
        baseTextColorID: String,
        labelTextColorID: String,
        isAutoTextContrastEnabled: Bool,
        colorAdjustments: [String: ColorAdjustment]
    ) {
        self.pollingIntervalInSeconds = pollingIntervalInSeconds
        self.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled
        self.enabledMetricIDs = normalizeEnabledMetricIDs(metricIDs: enabledMetricIDs)
        self.orderedMetricIDs = normalizeMetricOrder(metricIDs: orderedMetricIDs)
        isGpuEnabled = self.enabledMetricIDs.contains(gpuMetricID)
        self.gpuPollingMultiplier = clamp(
            value: gpuPollingMultiplier,
            fallback: defaultGpuPollingMultiplier,
            minValue: minimumGpuPollingMultiplier,
            maxValue: maximumGpuPollingMultiplier
        )
        self.warningThresholdPercent = clamp(value: warningThresholdPercent, fallback: defaultWarningThresholdPercent, minValue: minimumWarningThresholdPercent, maxValue: maximumWarningThresholdPercent)
        self.yellowThresholdPercent = clamp(
            value: yellowThresholdPercent,
            fallback: defaultYellowThresholdPercent,
            minValue: minimumWarningThresholdPercent,
            maxValue: max(minimumWarningThresholdPercent, self.warningThresholdPercent - 1)
        )
        self.yellowColorID = yellowColorID
        self.warningColorID = warningColorID
        self.uploadColorID = uploadColorID
        self.downloadColorID = downloadColorID
        self.baseTextColorID = baseTextColorID
        self.labelTextColorID = labelTextColorID
        self.isAutoTextContrastEnabled = isAutoTextContrastEnabled
        self.colorAdjustments = colorRoles.reduce(into: [String: ColorAdjustment]()) { colorAdjustmentsByRole, colorRole in
            let colorAdjustment = getColorAdjustment(colorAdjustments: colorAdjustments, roleID: colorRole.id)
            colorAdjustmentsByRole[colorRole.id] = ColorAdjustment(
                huePercent: clamp(value: colorAdjustment.huePercent, fallback: 0, minValue: minimumColorAdjustmentPercent, maxValue: maximumColorAdjustmentPercent),
                saturationPercent: clamp(value: colorAdjustment.saturationPercent, fallback: 0, minValue: minimumColorAdjustmentPercent, maxValue: maximumColorAdjustmentPercent),
                lightnessPercent: clamp(value: colorAdjustment.lightnessPercent, fallback: 0, minValue: minimumColorAdjustmentPercent, maxValue: maximumColorAdjustmentPercent)
            )
        }
        yellowColor = applyColorAdjustment(color: getColorPreset(id: yellowColorID)?.color ?? NSColor(srgbRed: 0.72, green: 0.54, blue: 0.00, alpha: 1), colorAdjustment: getColorAdjustment(colorAdjustments: self.colorAdjustments, roleID: yellowColorKey))
        warningColor = applyColorAdjustment(color: getColorPreset(id: warningColorID)?.color ?? .systemRed, colorAdjustment: getColorAdjustment(colorAdjustments: self.colorAdjustments, roleID: warningColorKey))
        uploadColor = applyColorAdjustment(color: getColorPreset(id: uploadColorID)?.color ?? .systemPurple, colorAdjustment: getColorAdjustment(colorAdjustments: self.colorAdjustments, roleID: uploadColorKey))
        downloadColor = applyColorAdjustment(color: getColorPreset(id: downloadColorID)?.color ?? .systemBlue, colorAdjustment: getColorAdjustment(colorAdjustments: self.colorAdjustments, roleID: downloadColorKey))
        baseTextColor = applyColorAdjustment(color: getTextColorPreset(id: baseTextColorID)?.color ?? .white, colorAdjustment: getColorAdjustment(colorAdjustments: self.colorAdjustments, roleID: baseTextColorKey))
        labelTextColor = applyColorAdjustment(color: getTextColorPreset(id: labelTextColorID)?.color ?? .white, colorAdjustment: getColorAdjustment(colorAdjustments: self.colorAdjustments, roleID: labelTextColorKey))
    }
}

func getMetricConfiguration(id maybeMetricID: String) -> MetricConfiguration? {
    availableMetrics.first { metricConfiguration in
        metricConfiguration.id == maybeMetricID
    }
}

func normalizeMetricOrder(metricIDs: [String]) -> [String] {
    let availableMetricIDs = Set(availableMetrics.map(\.id))
    let requestedMetricIDs = metricIDs.filter { metricID in
        availableMetricIDs.contains(metricID)
    }
    let uniqueRequestedMetricIDs = requestedMetricIDs.reduce(into: [String]()) { orderedMetricIDs, metricID in
        guard !orderedMetricIDs.contains(metricID) else {
            return
        }

        orderedMetricIDs.append(metricID)
    }
    let missingMetricIDs = availableMetrics.map(\.id).filter { metricID in
        !uniqueRequestedMetricIDs.contains(metricID)
    }

    return uniqueRequestedMetricIDs + missingMetricIDs
}

func normalizeEnabledMetricIDs(metricIDs: Set<String>) -> Set<String> {
    let availableMetricIDs = Set(availableMetrics.map(\.id))
    return metricIDs.intersection(availableMetricIDs)
}

func getColorAdjustment(colorAdjustments: [String: ColorAdjustment], roleID: String) -> ColorAdjustment {
    colorAdjustments[roleID] ?? ColorAdjustment(huePercent: 0, saturationPercent: 0, lightnessPercent: 0)
}

func applyColorAdjustment(color: NSColor, colorAdjustment: ColorAdjustment) -> NSColor {
    guard let rgbColor = color.usingColorSpace(.sRGB) else {
        return color
    }

    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    let hslColor = getHslColor(red: red, green: green, blue: blue)
    let hueOffset = CGFloat(colorAdjustment.huePercent) / 100 * 0.08
    let saturationOffset = CGFloat(colorAdjustment.saturationPercent) / 100 * 0.35
    let lightnessOffset = CGFloat(colorAdjustment.lightnessPercent) / 100 * 0.35
    let adjustedHue = getWrappedHue(hslColor.hue + hueOffset)
    let adjustedSaturation = clamp(value: hslColor.saturation + saturationOffset, minValue: 0, maxValue: 1)
    let adjustedLightness = clamp(value: hslColor.lightness + lightnessOffset, minValue: 0.04, maxValue: 0.96)
    let adjustedRgbColor = getRgbColor(hue: adjustedHue, saturation: adjustedSaturation, lightness: adjustedLightness)

    return NSColor(
        srgbRed: adjustedRgbColor.red,
        green: adjustedRgbColor.green,
        blue: adjustedRgbColor.blue,
        alpha: alpha
    )
}

private func getHslColor(red: CGFloat, green: CGFloat, blue: CGFloat) -> (hue: CGFloat, saturation: CGFloat, lightness: CGFloat) {
    let maximumValue = max(red, max(green, blue))
    let minimumValue = min(red, min(green, blue))
    let lightness = (maximumValue + minimumValue) / 2
    let delta = maximumValue - minimumValue

    guard delta != 0 else {
        return (0, 0, lightness)
    }

    let saturation = delta / (1 - abs(2 * lightness - 1))
    let hue: CGFloat

    if maximumValue == red {
        hue = getWrappedHue((green - blue) / delta / 6)
    } else if maximumValue == green {
        hue = ((blue - red) / delta + 2) / 6
    } else {
        hue = ((red - green) / delta + 4) / 6
    }

    return (hue, saturation, lightness)
}

private func getRgbColor(hue: CGFloat, saturation: CGFloat, lightness: CGFloat) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
    let chroma = (1 - abs(2 * lightness - 1)) * saturation
    let hueSegment = hue * 6
    let secondaryComponent = chroma * (1 - abs(hueSegment.truncatingRemainder(dividingBy: 2) - 1))
    let matchComponent = lightness - chroma / 2
    let rgbPrimeColor: (red: CGFloat, green: CGFloat, blue: CGFloat)

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
        blue: rgbPrimeColor.blue + matchComponent
    )
}

private func getWrappedHue(_ hue: CGFloat) -> CGFloat {
    if hue < 0 {
        return hue + 1
    }

    if hue > 1 {
        return hue - 1
    }

    return hue
}

private func clamp(value: TimeInterval, fallback: TimeInterval, minValue: TimeInterval, maxValue: TimeInterval) -> TimeInterval {
    if value < minValue {
        return fallback
    }

    if value > maxValue {
        return fallback
    }

    return value
}

private func clamp(value: Int, fallback: Int, minValue: Int, maxValue: Int) -> Int {
    if value < minValue {
        return fallback
    }

    if value > maxValue {
        return fallback
    }

    return value
}

private func clamp(value: CGFloat, minValue: CGFloat, maxValue: CGFloat) -> CGFloat {
    if value < minValue {
        return minValue
    }

    if value > maxValue {
        return maxValue
    }

    return value
}

import AppKit

let minimumPollingIntervalInSeconds: TimeInterval = 1
let maximumPollingIntervalInSeconds: TimeInterval = 60
let minimumGpuPollingMultiplier = 1
let maximumGpuPollingMultiplier = 20
let minimumWarningThresholdPercent = 1
let maximumWarningThresholdPercent = 100
let minimumBackgroundOpacityPercent = 10
let maximumBackgroundOpacityPercent = 100
let colorPresets = [
    ColorPreset(id: "red", title: "Red", color: NSColor(srgbRed: 0.86, green: 0.04, blue: 0.08, alpha: 1)),
    ColorPreset(id: "orange", title: "Orange", color: NSColor(srgbRed: 0.88, green: 0.28, blue: 0.00, alpha: 1)),
    ColorPreset(id: "yellow", title: "Yellow", color: NSColor(srgbRed: 0.72, green: 0.54, blue: 0.00, alpha: 1)),
    ColorPreset(id: "purple", title: "Purple", color: NSColor(srgbRed: 0.50, green: 0.12, blue: 0.88, alpha: 1)),
    ColorPreset(id: "blue", title: "Blue", color: NSColor(srgbRed: 0.00, green: 0.28, blue: 0.88, alpha: 1)),
    ColorPreset(id: "teal", title: "Teal", color: NSColor(srgbRed: 0.00, green: 0.56, blue: 0.62, alpha: 1)),
    ColorPreset(id: "green", title: "Green", color: NSColor(srgbRed: 0.00, green: 0.58, blue: 0.18, alpha: 1))
]

private let pollingIntervalKey = "pollingIntervalInSeconds"
private let isGpuEnabledKey = "isGpuEnabled"
private let gpuPollingMultiplierKey = "gpuPollingMultiplier"
private let legacyGpuPollingIntervalKey = "gpuPollingIntervalInSeconds"
private let yellowThresholdKey = "yellowThresholdPercent"
private let yellowColorKey = "yellowColor"
private let warningThresholdKey = "warningThresholdPercent"
private let warningColorKey = "warningColor"
private let uploadColorKey = "uploadColor"
private let downloadColorKey = "downloadColor"
private let isBackgroundEnabledKey = "isBackgroundEnabled"
private let backgroundHueKey = "backgroundHue"
private let backgroundSaturationKey = "backgroundSaturation"
private let backgroundOpacityPercentKey = "backgroundOpacityPercent"
private let defaultPollingIntervalInSeconds: TimeInterval = 3
private let defaultIsGpuEnabled = false
private let defaultGpuPollingMultiplier = 2
private let defaultYellowThresholdPercent = 60
private let defaultYellowColorID = "yellow"
private let defaultWarningThresholdPercent = 80
private let defaultWarningColorID = "red"
private let defaultUploadColorID = "purple"
private let defaultDownloadColorID = "blue"
private let defaultIsBackgroundEnabled = false
private let defaultBackgroundHue = 0.62
private let defaultBackgroundSaturation = 0.18
private let defaultBackgroundOpacityPercent = 82

struct AppConfiguration {
    let pollingIntervalInSeconds: TimeInterval
    let isGpuEnabled: Bool
    let gpuPollingMultiplier: Int
    let yellowThresholdPercent: Int
    let yellowColorID: String
    let warningThresholdPercent: Int
    let warningColorID: String
    let uploadColorID: String
    let downloadColorID: String
    let isBackgroundEnabled: Bool
    let backgroundHue: Double
    let backgroundSaturation: Double
    let backgroundOpacityPercent: Int
    let yellowColor: NSColor
    let warningColor: NSColor
    let uploadColor: NSColor
    let downloadColor: NSColor
    let backgroundColor: NSColor
}

struct ColorPreset {
    let id: String
    let title: String
    let color: NSColor
}

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
            isGpuEnabled: userDefaults.object(forKey: isGpuEnabledKey) as? Bool ?? defaultConfiguration.isGpuEnabled,
            gpuPollingMultiplier: gpuPollingMultiplier,
            yellowThresholdPercent: yellowThresholdPercent,
            yellowColorID: readColorID(forKey: yellowColorKey, fallback: defaultConfiguration.yellowColorID),
            warningThresholdPercent: warningThresholdPercent,
            warningColorID: readColorID(forKey: warningColorKey, fallback: defaultConfiguration.warningColorID),
            uploadColorID: readColorID(forKey: uploadColorKey, fallback: defaultConfiguration.uploadColorID),
            downloadColorID: readColorID(forKey: downloadColorKey, fallback: defaultConfiguration.downloadColorID),
            isBackgroundEnabled: userDefaults.object(forKey: isBackgroundEnabledKey) as? Bool ?? defaultConfiguration.isBackgroundEnabled,
            backgroundHue: readDouble(
                forKey: backgroundHueKey,
                fallback: defaultConfiguration.backgroundHue,
                minValue: 0,
                maxValue: 1
            ),
            backgroundSaturation: readDouble(
                forKey: backgroundSaturationKey,
                fallback: defaultConfiguration.backgroundSaturation,
                minValue: 0,
                maxValue: 1
            ),
            backgroundOpacityPercent: clamp(
                value: userDefaults.integer(forKey: backgroundOpacityPercentKey),
                fallback: defaultConfiguration.backgroundOpacityPercent,
                minValue: minimumBackgroundOpacityPercent,
                maxValue: maximumBackgroundOpacityPercent
            )
        )
    }

    func save(_ configuration: AppConfiguration) {
        userDefaults.set(configuration.pollingIntervalInSeconds, forKey: pollingIntervalKey)
        userDefaults.set(configuration.isGpuEnabled, forKey: isGpuEnabledKey)
        userDefaults.set(configuration.gpuPollingMultiplier, forKey: gpuPollingMultiplierKey)
        userDefaults.set(configuration.yellowThresholdPercent, forKey: yellowThresholdKey)
        userDefaults.set(configuration.yellowColorID, forKey: yellowColorKey)
        userDefaults.set(configuration.warningThresholdPercent, forKey: warningThresholdKey)
        userDefaults.set(configuration.warningColorID, forKey: warningColorKey)
        userDefaults.set(configuration.uploadColorID, forKey: uploadColorKey)
        userDefaults.set(configuration.downloadColorID, forKey: downloadColorKey)
        userDefaults.set(configuration.isBackgroundEnabled, forKey: isBackgroundEnabledKey)
        userDefaults.set(configuration.backgroundHue, forKey: backgroundHueKey)
        userDefaults.set(configuration.backgroundSaturation, forKey: backgroundSaturationKey)
        userDefaults.set(configuration.backgroundOpacityPercent, forKey: backgroundOpacityPercentKey)
    }

    private func readColorID(forKey key: String, fallback: String) -> String {
        let maybeColorID = userDefaults.string(forKey: key)

        return getColorPreset(id: maybeColorID)?.id ?? fallback
    }

    private func readDouble(forKey key: String, fallback: Double, minValue: Double, maxValue: Double) -> Double {
        guard userDefaults.object(forKey: key) != nil else {
            return fallback
        }

        return clamp(value: userDefaults.double(forKey: key), fallback: fallback, minValue: minValue, maxValue: maxValue)
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
        isGpuEnabled: defaultIsGpuEnabled,
        gpuPollingMultiplier: defaultGpuPollingMultiplier,
        yellowThresholdPercent: defaultYellowThresholdPercent,
        yellowColorID: defaultYellowColorID,
        warningThresholdPercent: defaultWarningThresholdPercent,
        warningColorID: defaultWarningColorID,
        uploadColorID: defaultUploadColorID,
        downloadColorID: defaultDownloadColorID,
        isBackgroundEnabled: defaultIsBackgroundEnabled,
        backgroundHue: defaultBackgroundHue,
        backgroundSaturation: defaultBackgroundSaturation,
        backgroundOpacityPercent: defaultBackgroundOpacityPercent
    )
}

func getColorPreset(id maybeColorID: String?) -> ColorPreset? {
    colorPresets.first { colorPreset in
        colorPreset.id == maybeColorID
    }
}

extension AppConfiguration {
    init(
        pollingIntervalInSeconds: TimeInterval,
        isGpuEnabled: Bool,
        gpuPollingMultiplier: Int,
        yellowThresholdPercent: Int,
        yellowColorID: String,
        warningThresholdPercent: Int,
        warningColorID: String,
        uploadColorID: String,
        downloadColorID: String,
        isBackgroundEnabled: Bool,
        backgroundHue: Double,
        backgroundSaturation: Double,
        backgroundOpacityPercent: Int
    ) {
        self.pollingIntervalInSeconds = pollingIntervalInSeconds
        self.isGpuEnabled = isGpuEnabled
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
        self.isBackgroundEnabled = isBackgroundEnabled
        self.backgroundHue = clamp(value: backgroundHue, fallback: defaultBackgroundHue, minValue: 0, maxValue: 1)
        self.backgroundSaturation = clamp(value: backgroundSaturation, fallback: defaultBackgroundSaturation, minValue: 0, maxValue: 1)
        self.backgroundOpacityPercent = clamp(
            value: backgroundOpacityPercent,
            fallback: defaultBackgroundOpacityPercent,
            minValue: minimumBackgroundOpacityPercent,
            maxValue: maximumBackgroundOpacityPercent
        )
        yellowColor = getColorPreset(id: yellowColorID)?.color ?? NSColor(srgbRed: 0.72, green: 0.54, blue: 0.00, alpha: 1)
        warningColor = getColorPreset(id: warningColorID)?.color ?? .systemRed
        uploadColor = getColorPreset(id: uploadColorID)?.color ?? .systemPurple
        downloadColor = getColorPreset(id: downloadColorID)?.color ?? .systemBlue
        backgroundColor = NSColor(
            calibratedHue: self.backgroundHue,
            saturation: self.backgroundSaturation,
            brightness: 0.18,
            alpha: CGFloat(self.backgroundOpacityPercent) / 100
        )
    }
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

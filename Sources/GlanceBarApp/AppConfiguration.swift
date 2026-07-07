import AppKit

let minimumPollingIntervalInSeconds: TimeInterval = 1
let maximumPollingIntervalInSeconds: TimeInterval = 60
let minimumWarningThresholdPercent = 1
let maximumWarningThresholdPercent = 100
let colorPresets = [
    ColorPreset(id: "red", title: "Red", color: NSColor(srgbRed: 0.78, green: 0.10, blue: 0.12, alpha: 1)),
    ColorPreset(id: "orange", title: "Orange", color: NSColor(srgbRed: 0.76, green: 0.32, blue: 0.00, alpha: 1)),
    ColorPreset(id: "purple", title: "Purple", color: NSColor(srgbRed: 0.46, green: 0.24, blue: 0.70, alpha: 1)),
    ColorPreset(id: "blue", title: "Blue", color: NSColor(srgbRed: 0.10, green: 0.34, blue: 0.74, alpha: 1)),
    ColorPreset(id: "teal", title: "Teal", color: NSColor(srgbRed: 0.00, green: 0.45, blue: 0.50, alpha: 1)),
    ColorPreset(id: "green", title: "Green", color: NSColor(srgbRed: 0.10, green: 0.48, blue: 0.20, alpha: 1))
]

private let pollingIntervalKey = "pollingIntervalInSeconds"
private let warningThresholdKey = "warningThresholdPercent"
private let warningColorKey = "warningColor"
private let uploadColorKey = "uploadColor"
private let downloadColorKey = "downloadColor"
private let defaultPollingIntervalInSeconds: TimeInterval = 3
private let defaultWarningThresholdPercent = 80
private let defaultWarningColorID = "red"
private let defaultUploadColorID = "purple"
private let defaultDownloadColorID = "blue"

struct AppConfiguration {
    let pollingIntervalInSeconds: TimeInterval
    let warningThresholdPercent: Int
    let warningColorID: String
    let uploadColorID: String
    let downloadColorID: String
    let warningColor: NSColor
    let uploadColor: NSColor
    let downloadColor: NSColor
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
        let warningThresholdPercent = clamp(
            value: userDefaults.integer(forKey: warningThresholdKey),
            fallback: defaultConfiguration.warningThresholdPercent,
            minValue: minimumWarningThresholdPercent,
            maxValue: maximumWarningThresholdPercent
        )

        return AppConfiguration(
            pollingIntervalInSeconds: pollingIntervalInSeconds,
            warningThresholdPercent: warningThresholdPercent,
            warningColorID: readColorID(forKey: warningColorKey, fallback: defaultConfiguration.warningColorID),
            uploadColorID: readColorID(forKey: uploadColorKey, fallback: defaultConfiguration.uploadColorID),
            downloadColorID: readColorID(forKey: downloadColorKey, fallback: defaultConfiguration.downloadColorID)
        )
    }

    func save(_ configuration: AppConfiguration) {
        userDefaults.set(configuration.pollingIntervalInSeconds, forKey: pollingIntervalKey)
        userDefaults.set(configuration.warningThresholdPercent, forKey: warningThresholdKey)
        userDefaults.set(configuration.warningColorID, forKey: warningColorKey)
        userDefaults.set(configuration.uploadColorID, forKey: uploadColorKey)
        userDefaults.set(configuration.downloadColorID, forKey: downloadColorKey)
    }

    private func readColorID(forKey key: String, fallback: String) -> String {
        let maybeColorID = userDefaults.string(forKey: key)

        return getColorPreset(id: maybeColorID)?.id ?? fallback
    }
}

func makeDefaultAppConfiguration() -> AppConfiguration {
    AppConfiguration(
        pollingIntervalInSeconds: defaultPollingIntervalInSeconds,
        warningThresholdPercent: defaultWarningThresholdPercent,
        warningColorID: defaultWarningColorID,
        uploadColorID: defaultUploadColorID,
        downloadColorID: defaultDownloadColorID
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
        warningThresholdPercent: Int,
        warningColorID: String,
        uploadColorID: String,
        downloadColorID: String
    ) {
        self.pollingIntervalInSeconds = pollingIntervalInSeconds
        self.warningThresholdPercent = warningThresholdPercent
        self.warningColorID = warningColorID
        self.uploadColorID = uploadColorID
        self.downloadColorID = downloadColorID
        warningColor = getColorPreset(id: warningColorID)?.color ?? .systemRed
        uploadColor = getColorPreset(id: uploadColorID)?.color ?? .systemPurple
        downloadColor = getColorPreset(id: downloadColorID)?.color ?? .systemBlue
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

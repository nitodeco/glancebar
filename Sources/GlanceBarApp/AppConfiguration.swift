import AppKit

let minimumPollingIntervalInSeconds: TimeInterval = 1
let maximumPollingIntervalInSeconds: TimeInterval = 60
let minimumWarningThresholdPercent = 1
let maximumWarningThresholdPercent = 100

private let pollingIntervalKey = "pollingIntervalInSeconds"
private let warningThresholdKey = "warningThresholdPercent"
private let warningColorKey = "warningColor"
private let uploadColorKey = "uploadColor"
private let downloadColorKey = "downloadColor"
private let defaultPollingIntervalInSeconds: TimeInterval = 3
private let defaultWarningThresholdPercent = 80

struct AppConfiguration {
    let pollingIntervalInSeconds: TimeInterval
    let warningThresholdPercent: Int
    let warningColor: NSColor
    let uploadColor: NSColor
    let downloadColor: NSColor
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
            warningColor: readColor(forKey: warningColorKey, fallback: defaultConfiguration.warningColor),
            uploadColor: readColor(forKey: uploadColorKey, fallback: defaultConfiguration.uploadColor),
            downloadColor: readColor(forKey: downloadColorKey, fallback: defaultConfiguration.downloadColor)
        )
    }

    func save(_ configuration: AppConfiguration) {
        userDefaults.set(configuration.pollingIntervalInSeconds, forKey: pollingIntervalKey)
        userDefaults.set(configuration.warningThresholdPercent, forKey: warningThresholdKey)
        saveColor(configuration.warningColor, forKey: warningColorKey)
        saveColor(configuration.uploadColor, forKey: uploadColorKey)
        saveColor(configuration.downloadColor, forKey: downloadColorKey)
    }

    private func readColor(forKey key: String, fallback: NSColor) -> NSColor {
        guard
            let maybeColorArchive = userDefaults.data(forKey: key),
            let maybeColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: maybeColorArchive)
        else {
            return fallback
        }

        return maybeColor
    }

    private func saveColor(_ color: NSColor, forKey key: String) {
        guard let maybeColorArchive = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) else {
            return
        }

        userDefaults.set(maybeColorArchive, forKey: key)
    }
}

func makeDefaultAppConfiguration() -> AppConfiguration {
    AppConfiguration(
        pollingIntervalInSeconds: defaultPollingIntervalInSeconds,
        warningThresholdPercent: defaultWarningThresholdPercent,
        warningColor: .systemRed,
        uploadColor: .systemPurple,
        downloadColor: .systemBlue
    )
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

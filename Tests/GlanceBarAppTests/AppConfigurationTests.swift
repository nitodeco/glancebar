import Foundation
import Testing
@testable import GlanceBarApp

private let appConfigurationTestSuiteNamePrefix = "dev.nitodeco.glancebar.tests.configuration"

private func makeTestUserDefaults() throws -> (userDefaults: UserDefaults, suiteName: String) {
    let suiteName = "\(appConfigurationTestSuiteNamePrefix).\(UUID().uuidString)"

    return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
}

@MainActor
@Test func rejectsNonFinitePollingInterval() throws {
    let (userDefaults, suiteName) = try makeTestUserDefaults()
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    userDefaults.set(Double.nan, forKey: "pollingIntervalInSeconds")

    #expect(AppConfigurationStore(userDefaults: userDefaults).load().pollingIntervalInSeconds == 3)
}

@MainActor
@Test func loadsRequestedFirstRunDefaults() throws {
    let (userDefaults, suiteName) = try makeTestUserDefaults()
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    let configuration = AppConfigurationStore(userDefaults: userDefaults).load()

    #expect(configuration.isLaunchAtLoginEnabled)
    #expect(configuration.pollingIntervalInSeconds == 3)
    #expect(configuration.gpuPollingMultiplier == 2)
    #expect(configuration.warningThresholdPercent == 75)
    #expect(configuration.criticalThresholdPercent == 90)
    #expect(configuration.enabledMetricIDs == Set([cpuMetricID, gpuMetricID, ramMetricID, ssdMetricID, networkMetricID]))
    #expect(configuration.orderedMetricIDs == [cpuMetricID, gpuMetricID, ramMetricID, ssdMetricID, networkMetricID])
    #expect(configuration.warningColorID == "yellow")
    #expect(configuration.criticalColorID == "red")
    #expect(configuration.uploadColorID == "purple")
    #expect(configuration.downloadColorID == "blue")
    #expect(configuration.baseTextColorID == "white")
    #expect(configuration.labelTextColorID == "white")
    #expect(configuration.isAutoTextContrastEnabled)
}

@MainActor
@Test func migratesLegacyThresholdAndColorSemantics() throws {
    let (userDefaults, suiteName) = try makeTestUserDefaults()
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    userDefaults.set(68, forKey: "yellowThresholdPercent")
    userDefaults.set(92, forKey: "warningThresholdPercent")
    userDefaults.set("orange", forKey: "yellowColor")
    userDefaults.set("purple", forKey: "warningColor")
    userDefaults.set(12, forKey: "yellowColorHueAdjustment")
    userDefaults.set(-18, forKey: "warningColorHueAdjustment")

    let configuration = AppConfigurationStore(userDefaults: userDefaults).load()

    #expect(configuration.warningThresholdPercent == 68)
    #expect(configuration.criticalThresholdPercent == 92)
    #expect(configuration.warningColorID == "orange")
    #expect(configuration.criticalColorID == "purple")
    #expect(configuration.colorAdjustments[warningColorKey]?.huePercent == 12)
    #expect(configuration.colorAdjustments[criticalColorKey]?.huePercent == -18)
}

@MainActor
@Test func persistsSemanticThresholdAndColorKeys() throws {
    let (userDefaults, suiteName) = try makeTestUserDefaults()
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    let defaultConfiguration = makeDefaultAppConfiguration()
    let configuration = AppConfiguration(
        pollingIntervalInSeconds: defaultConfiguration.pollingIntervalInSeconds,
        isLaunchAtLoginEnabled: defaultConfiguration.isLaunchAtLoginEnabled,
        enabledMetricIDs: defaultConfiguration.enabledMetricIDs,
        orderedMetricIDs: defaultConfiguration.orderedMetricIDs,
        gpuPollingMultiplier: defaultConfiguration.gpuPollingMultiplier,
        warningThresholdPercent: 70,
        warningColorID: "orange",
        criticalThresholdPercent: 95,
        criticalColorID: "purple",
        uploadColorID: defaultConfiguration.uploadColorID,
        downloadColorID: defaultConfiguration.downloadColorID,
        baseTextColorID: defaultConfiguration.baseTextColorID,
        labelTextColorID: defaultConfiguration.labelTextColorID,
        isAutoTextContrastEnabled: defaultConfiguration.isAutoTextContrastEnabled,
        colorAdjustments: defaultConfiguration.colorAdjustments
    )

    let configurationStore = AppConfigurationStore(userDefaults: userDefaults)
    configurationStore.save(configuration)
    let persistedConfiguration = configurationStore.load()

    #expect(persistedConfiguration.warningThresholdPercent == 70)
    #expect(persistedConfiguration.criticalThresholdPercent == 95)
    #expect(persistedConfiguration.warningColorID == "orange")
    #expect(persistedConfiguration.criticalColorID == "purple")
}

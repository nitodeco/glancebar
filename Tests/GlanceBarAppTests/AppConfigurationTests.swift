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

    userDefaults.set(Double.nan, forKey: "cpuPollingIntervalInSeconds")

    #expect(AppConfigurationStore(userDefaults: userDefaults).load().pollingIntervalInSeconds(metricID: cpuMetricID) == 3)
}

@MainActor
@Test func loadsRequestedFirstRunDefaults() throws {
    let (userDefaults, suiteName) = try makeTestUserDefaults()
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    let configuration = AppConfigurationStore(userDefaults: userDefaults).load()

    #expect(configuration.isLaunchAtLoginEnabled)
    #expect(configuration.pollingIntervalInSeconds(metricID: cpuMetricID) == 3)
    #expect(configuration.pollingIntervalInSeconds(metricID: gpuMetricID) == 9)
    #expect(configuration.pollingIntervalInSeconds(metricID: ramMetricID) == 3)
    #expect(configuration.pollingIntervalInSeconds(metricID: ssdMetricID) == 30)
    #expect(configuration.pollingIntervalInSeconds(metricID: networkMetricID) == 10)
    #expect(configuration.isLowPowerModePollingAdjustmentEnabled)
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
@Test func migratesLegacyPollingConfiguration() throws {
    let (userDefaults, suiteName) = try makeTestUserDefaults()
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    userDefaults.set(4.0, forKey: "pollingIntervalInSeconds")
    userDefaults.set(3, forKey: "gpuPollingMultiplier")

    let configuration = AppConfigurationStore(userDefaults: userDefaults).load()

    #expect(configuration.pollingIntervalInSeconds(metricID: cpuMetricID) == 4)
    #expect(configuration.pollingIntervalInSeconds(metricID: gpuMetricID) == 12)
    #expect(configuration.pollingIntervalInSeconds(metricID: ramMetricID) == 4)
    #expect(configuration.pollingIntervalInSeconds(metricID: ssdMetricID) == 30)
    #expect(configuration.pollingIntervalInSeconds(metricID: networkMetricID) == 4)
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
        isLaunchAtLoginEnabled: defaultConfiguration.isLaunchAtLoginEnabled,
        enabledMetricIDs: defaultConfiguration.enabledMetricIDs,
        orderedMetricIDs: defaultConfiguration.orderedMetricIDs,
        pollingIntervalsByMetricID: [
            cpuMetricID: 2,
            gpuMetricID: 8,
            ramMetricID: 4,
            ssdMetricID: 40,
            networkMetricID: 12
        ],
        isLowPowerModePollingAdjustmentEnabled: false,
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
    #expect(persistedConfiguration.pollingIntervalInSeconds(metricID: cpuMetricID) == 2)
    #expect(persistedConfiguration.pollingIntervalInSeconds(metricID: gpuMetricID) == 8)
    #expect(persistedConfiguration.pollingIntervalInSeconds(metricID: ramMetricID) == 4)
    #expect(persistedConfiguration.pollingIntervalInSeconds(metricID: ssdMetricID) == 40)
    #expect(persistedConfiguration.pollingIntervalInSeconds(metricID: networkMetricID) == 12)
    #expect(!persistedConfiguration.isLowPowerModePollingAdjustmentEnabled)
}

@MainActor
@Test func preservesDisabledGpuFromLegacyConfiguration() throws {
    let (userDefaults, suiteName) = try makeTestUserDefaults()
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
    userDefaults.set(false, forKey: "isGpuEnabled")

    let configuration = AppConfigurationStore(userDefaults: userDefaults).load()

    #expect(!configuration.enabledMetricIDs.contains(gpuMetricID))
}

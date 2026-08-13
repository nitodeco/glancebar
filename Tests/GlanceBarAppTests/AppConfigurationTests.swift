import Foundation
import Testing
@testable import GlanceBarApp

private let appConfigurationTestSuiteName = "dev.nitodeco.glancebar.tests.configuration"

@MainActor
@Test func rejectsNonFinitePollingInterval() throws {
    let userDefaults = try #require(UserDefaults(suiteName: appConfigurationTestSuiteName))
    userDefaults.removePersistentDomain(forName: appConfigurationTestSuiteName)
    defer {
        userDefaults.removePersistentDomain(forName: appConfigurationTestSuiteName)
    }

    userDefaults.set(Double.nan, forKey: "pollingIntervalInSeconds")

    #expect(AppConfigurationStore(userDefaults: userDefaults).load().pollingIntervalInSeconds == 3)
}

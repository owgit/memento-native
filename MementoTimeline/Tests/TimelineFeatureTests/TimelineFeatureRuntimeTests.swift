import XCTest
@testable import TimelineFeature

final class TimelineFeatureRuntimeTests: XCTestCase {
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "TimelineFeatureRuntimeTests.\(UUID().uuidString)"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        await MainActor.run {
            TimelineFeatureRuntime.clearConfiguration()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            TimelineFeatureRuntime.clearConfiguration()
        }
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        suiteName = nil
        try await super.tearDown()
    }

    func testRuntimeConfigurationOverridesDefaults() async {
        let suiteName = self.suiteName!
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("/tmp/default-storage", forKey: "storagePath")
        defaults.set(3.0, forKey: "captureInterval")

        await MainActor.run {
            TimelineFeatureRuntime.configure {
                TimelineFeatureConfiguration(
                    storagePath: "/tmp/runtime-storage",
                    captureInterval: 5.0
                )
            }
        }

        let storagePath = await MainActor.run {
            TimelineSettingsAccess.resolveStoragePath(
                defaults: UserDefaults(suiteName: suiteName)!
            )
        }
        let captureInterval = await MainActor.run {
            TimelineSettingsAccess.resolveCaptureInterval(
                defaults: UserDefaults(suiteName: suiteName)!
            )
        }

        XCTAssertEqual(storagePath, "/tmp/runtime-storage")
        XCTAssertEqual(captureInterval, 5.0, accuracy: 0.001)
    }

    func testDefaultsAreUsedWhenRuntimeConfigurationIsMissing() async {
        let suiteName = self.suiteName!
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("/tmp/default-storage", forKey: "storagePath")
        defaults.set(4.0, forKey: "captureInterval")

        let storagePath = await MainActor.run {
            TimelineSettingsAccess.resolveStoragePath(
                defaults: UserDefaults(suiteName: suiteName)!
            )
        }
        let captureInterval = await MainActor.run {
            TimelineSettingsAccess.resolveCaptureInterval(
                defaults: UserDefaults(suiteName: suiteName)!
            )
        }

        XCTAssertEqual(storagePath, "/tmp/default-storage")
        XCTAssertEqual(captureInterval, 4.0, accuracy: 0.001)
    }

    func testFallbackValuesRemainStable() async {
        let suiteName = self.suiteName!
        let storagePath = await MainActor.run {
            TimelineSettingsAccess.resolveStoragePath(
                defaults: UserDefaults(suiteName: suiteName)!
            )
        }
        let captureInterval = await MainActor.run {
            TimelineSettingsAccess.resolveCaptureInterval(
                defaults: UserDefaults(suiteName: suiteName)!
            )
        }

        XCTAssertEqual(storagePath, AppRuntimeInfo.defaultStoragePath)
        XCTAssertEqual(captureInterval, 2.0, accuracy: 0.001)
    }
}

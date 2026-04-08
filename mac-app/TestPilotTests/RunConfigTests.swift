import XCTest
@testable import TestPilotApp

final class RunConfigTests: XCTestCase {
    func testIsValidRequiresDeviceAppAndObjective() {
        let config = RunConfig()
        XCTAssertFalse(config.isValid, "empty config should be invalid")

        config.appName = "Pharmia"
        config.objective = "Check onboarding"
        XCTAssertFalse(config.isValid, "missing device should be invalid")

        config.selectedDevice = DeviceInfo(id: "abc", name: "iPhone 15", type: .simulator)
        XCTAssertTrue(config.isValid, "all required fields filled should be valid")
    }

    func testIsValidRejectsWhitespaceOnly() {
        let config = RunConfig()
        config.selectedDevice = DeviceInfo(id: "abc", name: "iPhone 15", type: .simulator)
        config.appName = "   "
        config.objective = "   "
        XCTAssertFalse(config.isValid, "whitespace-only fields should be invalid")
    }
}

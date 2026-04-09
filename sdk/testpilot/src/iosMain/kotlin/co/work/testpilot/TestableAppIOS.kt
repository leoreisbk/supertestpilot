package co.work.testpilot

import co.work.testpilot.throwables.TestAutomationException
import platform.XCTest.XCUIApplication
import platform.XCTest.XCUIElementSnapshotProvidingProtocol

class TestableAppIOS(bundleId: String? = null) : TestableApp<AppUISnapshotIOS> {
    val xcApp = if (bundleId != null) {
        XCUIApplication(bundleId)
    } else {
        XCUIApplication()
    }

    override suspend fun launch() {
        xcApp.launch()
    }

    override suspend fun snapshot(): AppUISnapshotIOS {
        val snapshotProvider = xcApp as XCUIElementSnapshotProvidingProtocol
        val snapshot = snapshotProvider.snapshotWithError(null)
            ?: throw TestAutomationException.SnapshotFailed()
        return AppUISnapshotIOS(snapshot)
    }
}

package co.work.testpilot

import co.work.testpilot.extensions.simplifyUI
import platform.XCTest.XCUIApplication

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
        return AppUISnapshotIOS(xcApp.debugDescription)
    }
}

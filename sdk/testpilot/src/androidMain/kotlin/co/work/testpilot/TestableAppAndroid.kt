package co.work.testpilot

import android.app.Application
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import co.work.testpilot.throwables.TestAutomationException
import kotlin.test.assertNotNull

class TestableAppAndroid : TestableApp<AppUISnapshotAndroid> {
    val instrumentation = InstrumentationRegistry.getInstrumentation()
    val device = UiDevice.getInstance(instrumentation)
    val application = ApplicationProvider.getApplicationContext() as? Application ?: throw TestAutomationException.AppNotFound()
    val packageName = application.packageName

    override suspend fun launch() {
        // Wait for launcher
        val launcherPackage: String = device.launcherPackageName
        assertNotNull(launcherPackage)
        device.wait(
            Until.hasObject(By.pkg(launcherPackage).depth(0)),
            5000L // TODO: centralize this timeout constant
        )

        // Launch the app
        val intent = application.packageManager.getLaunchIntentForPackage(packageName) ?: throw TestAutomationException.AppLaunchFailed(packageName)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
        application.startActivity(intent)

        // Wait for the app to appear
        device.wait(
            Until.hasObject(By.pkg(packageName).depth(0)),
            5000L
        )
        device.waitForIdle()
    }

    override suspend fun snapshot(): AppUISnapshotAndroid {
        val allPackageElements = device.findObjects(By.pkg(packageName).depth(0))
        return AppUISnapshotAndroid(allPackageElements)
    }
}

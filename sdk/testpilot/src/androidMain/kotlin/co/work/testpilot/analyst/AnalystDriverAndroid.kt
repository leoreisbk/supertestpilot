package co.work.testpilot.analyst

import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import java.io.File

class AnalystDriverAndroid : AnalystDriver {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)

    override suspend fun screenshotPng(): ByteArray {
        val tmpFile = File(instrumentation.context.cacheDir, "testpilot_screenshot.png")
        device.takeScreenshot(tmpFile, 0.5f, 80)
        val bytes = tmpFile.readBytes()
        tmpFile.delete()
        return bytes
    }

    override suspend fun tap(x: Double, y: Double) {
        val screenWidth = device.displayWidth
        val screenHeight = device.displayHeight
        device.click((x * screenWidth).toInt(), (y * screenHeight).toInt())
        device.waitForIdle()
    }

    override suspend fun scroll(direction: String) {
        val w = device.displayWidth
        val h = device.displayHeight
        // 40% scroll distance for controlled, precise scrolling
        val from = (h * 0.35).toInt()
        val to   = (h * 0.65).toInt()
        if (direction == "down") {
            device.swipe(w / 2, to, w / 2, from, 25)
        } else {
            device.swipe(w / 2, from, w / 2, to, 25)
        }
        device.waitForIdle()
    }

    override suspend fun type(x: Double, y: Double, text: String) {
        tap(x, y)
        device.waitForIdle()
        instrumentation.sendStringSync(text)
        device.waitForIdle()
    }
}

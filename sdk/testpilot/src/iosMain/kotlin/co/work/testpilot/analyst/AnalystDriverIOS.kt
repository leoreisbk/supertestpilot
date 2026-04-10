package co.work.testpilot.analyst

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.cValue
import kotlinx.cinterop.readBytes
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import platform.CoreGraphics.CGVector
import platform.XCTest.XCUIApplication
import platform.XCTest.XCUIGestureVelocitySlow
import platform.XCTest.XCUIScreen

@OptIn(ExperimentalForeignApi::class)
class AnalystDriverIOS(private val xcApp: XCUIApplication) : AnalystDriver {

    override suspend fun screenshotPng(): ByteArray = withContext(Dispatchers.Main) {
        val screenshot = XCUIScreen.mainScreen.screenshot()
        val data = screenshot.PNGRepresentation
        val bytes = data.bytes ?: return@withContext ByteArray(0)
        bytes.readBytes(data.length.toInt())
    }

    override suspend fun tap(x: Double, y: Double) {
        withContext(Dispatchers.Main) {
            val vector = cValue<CGVector> { dx = x; dy = y }
            xcApp.coordinateWithNormalizedOffset(vector).tap()
        }
        delay(600) // wait for transition animation to settle
    }

    override suspend fun scroll(direction: String) {
        withContext(Dispatchers.Main) {
            if (direction == "up") {
                xcApp.swipeUpWithVelocity(XCUIGestureVelocitySlow)
            } else {
                xcApp.swipeDownWithVelocity(XCUIGestureVelocitySlow)
            }
        }
        delay(400) // wait for scroll deceleration
    }

    override suspend fun type(x: Double, y: Double, text: String) {
        withContext(Dispatchers.Main) {
            val vector = cValue<CGVector> { dx = x; dy = y }
            val coord = xcApp.coordinateWithNormalizedOffset(vector)
            coord.tap()
            coord.typeText(text)
        }
        delay(800) // wait for keyboard and text to settle
    }
}

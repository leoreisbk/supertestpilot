package co.work.testpilot.analyst

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.cValue
import kotlinx.cinterop.readBytes
import platform.CoreGraphics.CGVector
import platform.XCTest.XCUIApplication
import platform.XCTest.XCUIGestureVelocitySlow
import platform.XCTest.XCUIScreen

@OptIn(ExperimentalForeignApi::class)
class AnalystDriverIOS(private val xcApp: XCUIApplication) : AnalystDriver {

    override suspend fun screenshotPng(): ByteArray {
        val screenshot = XCUIScreen.mainScreen.screenshot()
        val data = screenshot.PNGRepresentation
        val bytes = data.bytes ?: return ByteArray(0)
        return bytes.readBytes(data.length.toInt())
    }

    override suspend fun tap(x: Double, y: Double) {
        val vector = cValue<CGVector> { dx = x; dy = y }
        val coord = xcApp.coordinateWithNormalizedOffset(vector)
        coord.tap()
    }

    override suspend fun scroll(direction: String) {
        if (direction == "up") {
            xcApp.swipeUpWithVelocity(XCUIGestureVelocitySlow)
        } else {
            xcApp.swipeDownWithVelocity(XCUIGestureVelocitySlow)
        }
    }

    override suspend fun type(x: Double, y: Double, text: String) {
        val vector = cValue<CGVector> { dx = x; dy = y }
        val coord = xcApp.coordinateWithNormalizedOffset(vector)
        coord.tap()
        coord.typeText(text)
    }
}

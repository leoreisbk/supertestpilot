package co.work.testpilot.analyst

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.cValue
import kotlinx.cinterop.readBytes
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import platform.CoreGraphics.CGRect
import platform.CoreGraphics.CGSize
import platform.CoreGraphics.CGVector
import platform.UIKit.UIGraphicsBeginImageContextWithOptions
import platform.UIKit.UIGraphicsEndImageContext
import platform.UIKit.UIGraphicsGetImageFromCurrentImageContext
import platform.UIKit.UIImagePNGRepresentation
import platform.XCTest.XCUIApplication
import platform.XCTest.XCUIGestureVelocitySlow
import platform.XCTest.XCUIScreen

@OptIn(ExperimentalForeignApi::class)
class AnalystDriverIOS(private val xcApp: XCUIApplication) : AnalystDriver {

    override suspend fun screenshotPng(): ByteArray = withContext(Dispatchers.Main) {
        val screenshot = XCUIScreen.mainScreen.screenshot()
        val original = screenshot.image
        val originalWidth = original.size.useContents { width }

        // Downscale to 780px wide (@2x logical) — reduces 3x retina screenshots by ~60%
        val targetWidth = 780.0
        if (originalWidth <= targetWidth) {
            val data = screenshot.PNGRepresentation
            val bytes = data.bytes ?: return@withContext ByteArray(0)
            return@withContext bytes.readBytes(data.length.toInt())
        }

        val scale = targetWidth / originalWidth
        val targetHeight = original.size.useContents { height } * scale

        UIGraphicsBeginImageContextWithOptions(
            cValue<CGSize> { width = targetWidth; height = targetHeight },
            false,
            1.0,
        )
        original.drawInRect(
            cValue<CGRect> {
                origin.x = 0.0; origin.y = 0.0
                size.width = targetWidth; size.height = targetHeight
            }
        )
        val resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        val pngData = resized?.let { UIImagePNGRepresentation(it) }
            ?: screenshot.PNGRepresentation
        val bytes = pngData.bytes ?: return@withContext ByteArray(0)
        bytes.readBytes(pngData.length.toInt())
    }

    override suspend fun tap(x: Double, y: Double) = withContext(Dispatchers.Main) {
        val vector = cValue<CGVector> { dx = x; dy = y }
        val coord = xcApp.coordinateWithNormalizedOffset(vector)
        coord.tap()
    }

    override suspend fun scroll(direction: String) = withContext(Dispatchers.Main) {
        if (direction == "up") {
            xcApp.swipeUpWithVelocity(XCUIGestureVelocitySlow)
        } else {
            xcApp.swipeDownWithVelocity(XCUIGestureVelocitySlow)
        }
    }

    override suspend fun type(x: Double, y: Double, text: String) = withContext(Dispatchers.Main) {
        val vector = cValue<CGVector> { dx = x; dy = y }
        val coord = xcApp.coordinateWithNormalizedOffset(vector)
        coord.tap()
        coord.typeText(text)
    }
}

package co.work.testpilot.analyst

import co.work.testpilot.extensions.toTestPilotElementType
import co.work.testpilot.runtime.ElementType
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.cValue
import kotlinx.cinterop.readBytes
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import platform.CoreGraphics.CGRect
import platform.CoreGraphics.CGSize
import platform.CoreGraphics.CGVector
import platform.UIKit.UIGraphicsBeginImageContextWithOptions
import platform.UIKit.UIGraphicsEndImageContext
import platform.UIKit.UIGraphicsGetImageFromCurrentImageContext
import platform.UIKit.UIImage
import platform.UIKit.UIImageJPEGRepresentation
import platform.XCTest.XCUIApplication
import platform.XCTest.XCUIElementSnapshotProtocol
import platform.XCTest.XCUIElementSnapshotProvidingProtocol
import platform.XCTest.XCUIGestureVelocitySlow
import platform.XCTest.XCUIScreen

@OptIn(ExperimentalForeignApi::class)
class AnalystDriverIOS(private val xcApp: XCUIApplication) : AnalystDriver {

    override suspend fun screenshotPng(): ByteArray = withContext(Dispatchers.Main) {
        val screenshot = XCUIScreen.mainScreen.screenshot()
        val pngData = screenshot.PNGRepresentation ?: return@withContext ByteArray(0)
        // Resize to 50% and encode as JPEG to reduce token cost (~4-6x smaller than full PNG)
        val image = UIImage(data = pngData) ?: return@withContext pngData.bytes?.readBytes(pngData.length.toInt()) ?: ByteArray(0)
        val w = image.size.useContents { width }
        val h = image.size.useContents { height }
        UIGraphicsBeginImageContextWithOptions(cValue<CGSize> { width = w / 2.0; height = h / 2.0 }, false, 1.0)
        image.drawInRect(cValue<CGRect> { origin.x = 0.0; origin.y = 0.0; size.width = w / 2.0; size.height = h / 2.0 })
        val resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        val jpegData = UIImageJPEGRepresentation(resized ?: image, 0.75) ?: return@withContext ByteArray(0)
        jpegData.bytes?.readBytes(jpegData.length.toInt()) ?: ByteArray(0)
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

    override suspend fun accessibilityTree(): String = withContext(Dispatchers.Main) {
        val snapshot = (xcApp as XCUIElementSnapshotProvidingProtocol).snapshotWithError(null)
            ?: return@withContext ""
        val sb = StringBuilder()
        buildTree(snapshot, sb, 0, 0)
        sb.toString().trimEnd()
    }

    private fun buildTree(
        snapshot: XCUIElementSnapshotProtocol,
        sb: StringBuilder,
        depth: Int,
        count: Int,
    ): Int {
        if (depth > 6 || count >= 200) return count
        val elementType = snapshot.elementType.toTestPilotElementType()
        // Skip keyboard — it produces hundreds of individual key elements
        if (elementType == ElementType.Keyboard) return count
        val label = snapshot.label
        val value = snapshot.value as? String
        var currentCount = count
        if (label.isNotEmpty() || !value.isNullOrEmpty()) {
            sb.append("  ".repeat(depth))
            sb.append(elementType.name)
            if (label.isNotEmpty()) sb.append(" \"$label\"")
            if (!value.isNullOrEmpty() && value != label) sb.append(" [${value.take(80)}]")
            sb.append("\n")
            currentCount++
        }
        @Suppress("UNCHECKED_CAST")
        for (child in snapshot.children as List<*>) {
            if (currentCount >= 200) break
            currentCount = buildTree(child as XCUIElementSnapshotProtocol, sb, depth + 1, currentCount)
        }
        return currentCount
    }
}

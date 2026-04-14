package co.work.testpilot.analyst

import co.work.testpilot.extensions.toTestPilotElementType
import co.work.testpilot.runtime.ElementType
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.cValue
import kotlinx.cinterop.readBytes
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import platform.CoreGraphics.CGVector
import platform.UIKit.UIImage
import platform.UIKit.UIImageJPEGRepresentation
import platform.XCTest.XCUIApplication
import platform.XCTest.XCUIElementSnapshotProtocol
import platform.XCTest.XCUIElementSnapshotProvidingProtocol
import platform.XCTest.XCUIElementTypeKeyboard
import platform.XCTest.XCUIGestureVelocitySlow
import platform.XCTest.XCUIScreen

@OptIn(ExperimentalForeignApi::class)
class AnalystDriverIOS(private val xcApp: XCUIApplication) : AnalystDriver {

    // Captures raw PNG NSData on main thread (XCTest requirement).
    // Returns NSData directly to avoid a ByteArray copy before encoding.
    private suspend fun captureRawPngData(): platform.Foundation.NSData? = withContext(Dispatchers.Main) {
        XCUIScreen.mainScreen.screenshot().PNGRepresentation
    }

    // Encodes PNG NSData → JPEG ByteArray on background thread (CPU work, no main-thread requirement)
    private suspend fun encodeJpeg(pngData: platform.Foundation.NSData): ByteArray = withContext(Dispatchers.Default) {
        val image = UIImage(data = pngData) ?: run {
            val bytes = pngData.bytes ?: return@withContext ByteArray(0)
            return@withContext bytes.readBytes(pngData.length.toInt())
        }
        val jpegData = UIImageJPEGRepresentation(image, 0.7) ?: run {
            val bytes = pngData.bytes ?: return@withContext ByteArray(0)
            return@withContext bytes.readBytes(pngData.length.toInt())
        }
        val bytes = jpegData.bytes ?: return@withContext ByteArray(0)
        bytes.readBytes(jpegData.length.toInt())
    }

    override suspend fun screenshotPng(): ByteArray {
        val pngData = captureRawPngData() ?: return ByteArray(0)
        return encodeJpeg(pngData)
    }

    // Parallel capture: JPEG encoding overlaps with accessibility tree capture (~100ms saved per step)
    override suspend fun captureStep(): Pair<ByteArray, String> = coroutineScope {
        val pngData = captureRawPngData() ?: return@coroutineScope Pair(ByteArray(0), "")
        // Launch JPEG encoding on background — runs concurrently with tree capture below
        val jpegDeferred = async(Dispatchers.Default) { encodeJpeg(pngData) }
        val tree = accessibilityTree()  // main thread, runs while encoding
        val jpeg = jpegDeferred.await()
        Pair(jpeg, tree)
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
            xcApp.coordinateWithNormalizedOffset(vector).tap()
        }
        delay(600)
        withContext(Dispatchers.Main) {
            // Wait for keyboard to appear before typing — avoids crashing when the
            // tapped element hasn't gained focus yet (e.g. tap opened a modal first).
            // Skip silently if no keyboard appears within 2 seconds.
            val appeared = xcApp.descendantsMatchingType(XCUIElementTypeKeyboard)!!
                .firstMatch.waitForExistenceWithTimeout(2.0)
            if (appeared) xcApp.typeText(text)
        }
        delay(400)
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

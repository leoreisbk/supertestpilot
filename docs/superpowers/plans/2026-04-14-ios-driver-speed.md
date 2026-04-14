# iOS Driver Speed Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overlap JPEG encoding with accessibility tree capture so both run concurrently, saving ~100ms per step (~4 seconds over a 40-step run).

**Architecture:** Add `captureStep()` with a default sequential implementation to the `AnalystDriver` interface, override it in `AnalystDriverIOS` with a parallel version using `coroutineScope { async }`, then update `Analyst.run()` to call `captureStep()` instead of two sequential calls.

**Tech Stack:** Kotlin Multiplatform (commonMain + iosMain), Kotlin Coroutines (`coroutineScope`, `async`, `Dispatchers.Default`, `Dispatchers.Main`)

---

## Files

| File | Change |
|------|--------|
| `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/AnalystDriver.kt` | Add `captureStep()` default method returning `Pair<ByteArray, String>` |
| `sdk/testpilot/src/iosMain/kotlin/co/work/testpilot/analyst/AnalystDriverIOS.kt` | Split `screenshotPng()` into `captureRawPng()` + `encodeJpeg()`, add parallel `captureStep()` override |
| `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/Analyst.kt` | Replace sequential `screenshotPng()` + `accessibilityTree()` calls with `captureStep()` |

---

### Task 1: Add `captureStep()` to `AnalystDriver` interface

**Files:**
- Modify: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/AnalystDriver.kt`

The default implementation calls both methods sequentially so Android and any other platform implementations work without changes.

- [ ] **Step 1: Add `captureStep()` default method**

Replace the entire file content with:

```kotlin
package co.work.testpilot.analyst

/** Lightweight fingerprint: sample every 200th byte to detect identical screens. */
internal fun screenFingerprint(png: ByteArray): Int {
    var sum = 0
    var i = 0
    while (i < png.size) { sum += png[i].toInt(); i += 200 }
    return sum
}

interface AnalystDriver {
    /** Capture the current screen as a PNG byte array. */
    suspend fun screenshotPng(): ByteArray

    /** Tap at relative screen coordinates (0.0–1.0). */
    suspend fun tap(x: Double, y: Double)

    /** Scroll in the given direction ("up" or "down"). */
    suspend fun scroll(direction: String)

    /** Tap a field at relative coordinates, then type text. */
    suspend fun type(x: Double, y: Double, text: String)

    /** Return a compact text representation of the UI element tree, or empty string if unavailable. */
    suspend fun accessibilityTree(): String = ""

    /**
     * Capture screenshot and accessibility tree.
     * Default: sequential. iOS overrides with a parallel implementation that overlaps
     * JPEG encoding (background thread) with tree capture (main thread).
     */
    suspend fun captureStep(): Pair<ByteArray, String> =
        Pair(screenshotPng(), accessibilityTree())
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
cd /Users/leonardo.reis/Projects/WorkCo/testpilot/sdk && ./gradlew testpilot:compileKotlinIosArm64 2>&1 | grep -E "^e:|BUILD"
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

```bash
git add sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/AnalystDriver.kt
git commit -m "feat(sdk): add captureStep() to AnalystDriver with sequential default"
```

---

### Task 2: Override `captureStep()` in `AnalystDriverIOS` with parallel implementation

**Files:**
- Modify: `sdk/testpilot/src/iosMain/kotlin/co/work/testpilot/analyst/AnalystDriverIOS.kt`

Split `screenshotPng()` into two private helpers: `captureRawPng()` (must run on main thread) and `encodeJpeg()` (CPU work, runs on `Dispatchers.Default`). The new `captureStep()` launches JPEG encoding as an async job on the background thread and concurrently captures the accessibility tree on the main thread.

- [ ] **Step 1: Add `coroutineScope` import and split screenshot into two helpers**

Replace the imports and `screenshotPng()` function. The full updated file:

```kotlin
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
import platform.Foundation.NSData
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

    // Captures raw PNG on main thread (XCTest requirement)
    private suspend fun captureRawPng(): ByteArray = withContext(Dispatchers.Main) {
        val screenshot = XCUIScreen.mainScreen.screenshot()
        val pngData = screenshot.PNGRepresentation ?: return@withContext ByteArray(0)
        val bytes = pngData.bytes ?: return@withContext ByteArray(0)
        bytes.readBytes(pngData.length.toInt())
    }

    // Encodes PNG → JPEG on background thread (CPU work, no main-thread requirement)
    private suspend fun encodeJpeg(pngBytes: ByteArray): ByteArray = withContext(Dispatchers.Default) {
        val nsData = NSData(bytes = pngBytes, length = pngBytes.size.toULong())
        val image = UIImage(data = nsData) ?: return@withContext pngBytes
        val jpegData = UIImageJPEGRepresentation(image, 0.7) ?: return@withContext pngBytes
        val bytes = jpegData.bytes ?: return@withContext pngBytes
        bytes.readBytes(jpegData.length.toInt())
    }

    override suspend fun screenshotPng(): ByteArray {
        val png = captureRawPng()
        return encodeJpeg(png)
    }

    // Parallel capture: JPEG encoding overlaps with accessibility tree capture
    override suspend fun captureStep(): Pair<ByteArray, String> = coroutineScope {
        val pngBytes = captureRawPng()
        // Launch JPEG encoding on background — runs concurrently with tree capture below
        val jpegDeferred = async(Dispatchers.Default) { encodeJpeg(pngBytes) }
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
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
cd /Users/leonardo.reis/Projects/WorkCo/testpilot/sdk && ./gradlew testpilot:compileKotlinIosArm64 2>&1 | grep -E "^e:|BUILD"
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

```bash
git add sdk/testpilot/src/iosMain/kotlin/co/work/testpilot/analyst/AnalystDriverIOS.kt
git commit -m "perf(sdk): overlap JPEG encoding with accessibility tree capture in AnalystDriverIOS"
```

---

### Task 3: Update `Analyst.run()` to use `captureStep()`

**Files:**
- Modify: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/Analyst.kt:26-46`

Replace the two sequential calls (`driver.screenshotPng()` and `driver.accessibilityTree()`) with a single `driver.captureStep()`. The fingerprint check moves to after `captureStep()` using the screenshot bytes from the pair.

- [ ] **Step 1: Replace sequential calls with `captureStep()`**

In `Analyst.run()`, change the loop body from:

```kotlin
val screenshot = driver.screenshotPng()
val fp = screenFingerprint(screenshot)

stuckCount = if (fp == lastFingerprint) stuckCount + 1 else 0
lastFingerprint = fp

// Hard recovery: alternate scroll direction so repeated recoveries don't
// cancel each other out (e.g. stuck at top: up would do nothing).
if (stuckCount >= 5) {
    val direction = if (scrollRecoveryCount % 2 == 0) "up" else "down"
    driver.scroll(direction)
    scrollRecoveryCount++
    stuckCount = 0
    continue
}

val tree = driver.accessibilityTree()
```

To:

```kotlin
val (screenshot, tree) = driver.captureStep()
val fp = screenFingerprint(screenshot)

stuckCount = if (fp == lastFingerprint) stuckCount + 1 else 0
lastFingerprint = fp

// Hard recovery: alternate scroll direction so repeated recoveries don't
// cancel each other out (e.g. stuck at top: up would do nothing).
if (stuckCount >= 5) {
    val direction = if (scrollRecoveryCount % 2 == 0) "up" else "down"
    driver.scroll(direction)
    scrollRecoveryCount++
    stuckCount = 0
    continue
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
cd /Users/leonardo.reis/Projects/WorkCo/testpilot/sdk && ./gradlew testpilot:compileKotlinIosArm64 2>&1 | grep -E "^e:|BUILD"
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

```bash
git add sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/Analyst.kt
git commit -m "perf(sdk): use captureStep() in Analyst — overlaps screenshot encoding with tree capture"
```

---

### Task 4: Build XCFramework and verify

- [ ] **Step 1: Build full XCFramework**

```bash
cd /Users/leonardo.reis/Projects/WorkCo/testpilot && scripts/build_ios_sdk.sh 2>&1 | tail -8
```

Expected: `BUILD SUCCESSFUL` and `Artifacts deployed to ~/.testpilot`

- [ ] **Step 2: Run a short analysis and confirm no regressions**

```bash
./testpilot analyze --platform ios --app <any-installed-app> --objective "quick smoke test" --max-steps 3 2>&1 | tail -20
```

Expected: analysis completes normally, HTML report is generated.

- [ ] **Step 3: Confirm git log**

```bash
git log --oneline -5
```

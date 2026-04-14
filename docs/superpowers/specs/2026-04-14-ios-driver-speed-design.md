# iOS Driver Speed Optimization Design

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce wall-clock time per analysis step by overlapping JPEG encoding with accessibility tree capture, and moving encoding off the main thread.

**Architecture:** Two targeted changes in `AnalystDriverIOS` and one small change in `Analyst` — JPEG encoding moves to a background dispatcher, and encoding runs concurrently with tree capture using Kotlin coroutine `async/await`.

**Tech Stack:** Kotlin Multiplatform (iosMain), Kotlin Coroutines (`async`, `Dispatchers.Default`), XCTest cinterop

---

## Context

Each analysis loop iteration in `Analyst.run()` does this sequence:

```
screenshot (main thread) → fingerprint → tree (main thread) → AI call → action
```

The screenshot step today:
1. Captures PNG on main thread (`XCUIScreen.mainScreen.screenshot()`) — must stay on main thread
2. Converts PNG → JPEG synchronously on main thread (`UIImageJPEGRepresentation`) — does NOT need main thread
3. Returns JPEG bytes

The tree step:
1. Calls `xcApp.snapshotWithError(null)` on main thread — must stay on main thread
2. Builds string representation recursively — does NOT need main thread

These two operations are **independent** — neither depends on the other's result. Currently they run sequentially. With `async/await`, JPEG encoding can overlap with tree capture.

---

## Files

| File | Change |
|------|--------|
| `iosMain/.../analyst/AnalystDriverIOS.kt` | Split `screenshotPng()` into capture + encode; expose `screenshotAndTreeAsync()` that returns both concurrently |
| `commonMain/.../analyst/AnalystDriver.kt` | Add `screenshotPng()` + `accessibilityTree()` (no change) — OR add a combined `suspend fun captureStep()` returning a pair |
| `commonMain/.../analyst/Analyst.kt` | Call the new combined capture to get screenshot + tree in one await instead of two sequential calls |

---

## Design

### Current flow (sequential)

```
[Main thread]  captureScreenshot (PNG)
[Main thread]  encodeJpeg                    ← blocks main thread ~100ms
[Main thread]  captureAccessibilityTree      ← blocked until encode finishes
[Main thread]  buildTreeString
[Background]   AI call
```

### New flow (overlapped)

```
[Main thread]  captureScreenshot (PNG)
[Background]   encodeJpeg ─────────────────┐   ← runs concurrently
[Main thread]  captureAccessibilityTree    │
[Background]   buildTreeString             │   ← can also move off main thread
               await encode result ────────┘
[Background]   AI call
```

Encoding and tree building are both CPU work with no UI interaction — both can run on `Dispatchers.Default`.

### Implementation

**`AnalystDriverIOS`** — split `screenshotPng()`:

```kotlin
// Captures raw PNG bytes on main thread (XCTest requirement)
private suspend fun captureRawPng(): ByteArray = withContext(Dispatchers.Main) {
    val screenshot = XCUIScreen.mainScreen.screenshot()
    val pngData = screenshot.PNGRepresentation ?: return@withContext ByteArray(0)
    val bytes = pngData.bytes ?: return@withContext ByteArray(0)
    bytes.readBytes(pngData.length.toInt())
}

// Encodes PNG → JPEG on background thread
private suspend fun encodeJpeg(pngBytes: ByteArray): ByteArray = withContext(Dispatchers.Default) {
    val image = UIImage(data = NSData(bytes = pngBytes, length = pngBytes.size.toULong()))
    val jpegData = image?.let { UIImageJPEGRepresentation(it, 0.7) }
    if (jpegData != null) {
        val bytes = jpegData.bytes ?: return@withContext pngBytes
        bytes.readBytes(jpegData.length.toInt())
    } else pngBytes
}
```

**`AnalystDriverIOS`** — new combined capture:

```kotlin
suspend fun captureStep(): Pair<ByteArray, String> {
    val pngBytes = captureRawPng()
    // Launch JPEG encoding on background — runs concurrently with tree capture
    val jpegDeferred = CoroutineScope(Dispatchers.Default).async { encodeJpeg(pngBytes) }
    val tree = accessibilityTree()        // main thread, runs while encoding
    val jpeg = jpegDeferred.await()
    return Pair(jpeg, tree)
}
```

**`AnalystDriver` interface** — add `captureStep()`:

```kotlin
suspend fun captureStep(): Pair<ByteArray, String>
```

**`Analyst.run()`** — replace two sequential calls with one:

```kotlin
// Before:
val screenshot = driver.screenshotPng()
// ...
val tree = driver.accessibilityTree()

// After:
val (screenshot, tree) = driver.captureStep()
```

The fingerprint check moves to after `captureStep()`, using the screenshot bytes as before.

---

## Interface change — `AnalystDriver`

`AnalystDriver` is a `commonMain` interface with iOS and potentially Android/Web implementations. Adding `captureStep()` requires a default implementation or all platforms to implement it.

**Approach:** Add `captureStep()` with a default implementation that calls `screenshotPng()` + `accessibilityTree()` sequentially — so Android/Web get correct behaviour automatically, and iOS overrides it with the parallel version.

```kotlin
// commonMain AnalystDriver.kt
interface AnalystDriver {
    suspend fun screenshotPng(): ByteArray
    suspend fun accessibilityTree(): String
    // ...

    // Default: sequential. iOS overrides with parallel implementation.
    suspend fun captureStep(): Pair<ByteArray, String> =
        Pair(screenshotPng(), accessibilityTree())
}
```

---

## Error Handling

- If JPEG encoding fails on the background thread, fall back to the original PNG bytes (same as current fallback path).
- If `captureStep()` throws, `Analyst` treats it the same as any other driver exception — the loop exits.
- The `CoroutineScope` used for `async` inside `captureStep()` is scoped to the call, not leaked.

---

## Expected Impact

| Step count | Current encoding + tree time (est.) | After overlap (est.) | Saving per run |
|------------|--------------------------------------|----------------------|----------------|
| 40 steps   | ~200ms × 40 = 8s                     | ~100ms × 40 = 4s     | ~4 seconds     |

Numbers are estimates based on typical JPEG encoding (~100ms) and tree capture (~100ms) on a simulator. Actual savings depend on device and app complexity.

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
}

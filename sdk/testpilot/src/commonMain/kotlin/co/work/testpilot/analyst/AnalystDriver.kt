package co.work.testpilot.analyst

interface AnalystDriver {
    /** Capture the current screen as a PNG byte array. */
    suspend fun screenshotPng(): ByteArray

    /** Tap at relative screen coordinates (0.0–1.0). */
    suspend fun tap(x: Double, y: Double)

    /** Scroll in the given direction ("up" or "down"). */
    suspend fun scroll(direction: String)

    /** Tap a field at relative coordinates, then type text. */
    suspend fun type(x: Double, y: Double, text: String)
}

package co.work.testpilot.analyst

import com.microsoft.playwright.Page
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AnalystDriverWeb(private val page: Page) : AnalystDriver {

    override suspend fun screenshotPng(): ByteArray = withContext(Dispatchers.IO) {
        page.screenshot()
    }

    override suspend fun tap(x: Double, y: Double) = withContext(Dispatchers.IO) {
        page.mouse().click(x * VIEWPORT_WIDTH, y * VIEWPORT_HEIGHT)
    }

    override suspend fun scroll(direction: String) = withContext(Dispatchers.IO) {
        val delta = when (direction) {
            "down" -> 400.0
            else   -> -400.0
        }
        page.mouse().wheel(0.0, delta)
    }

    override suspend fun type(x: Double, y: Double, text: String) = withContext(Dispatchers.IO) {
        page.mouse().click(x * VIEWPORT_WIDTH, y * VIEWPORT_HEIGHT)
        page.keyboard().type(text)
    }

    companion object {
        const val VIEWPORT_WIDTH = 1280
        const val VIEWPORT_HEIGHT = 800
    }
}

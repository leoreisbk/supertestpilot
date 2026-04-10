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

    override suspend fun accessibilityTree(): String = withContext(Dispatchers.IO) {
        try {
            page.evaluate("""
                () => {
                    const items = [];
                    const seen = new Set();
                    document.querySelectorAll(
                        'button, a[href], input, select, textarea, [role], h1, h2, h3, h4, label'
                    ).forEach(el => {
                        if (items.length >= 200) return;
                        const tag = el.tagName.toLowerCase();
                        const role = el.getAttribute('role') || tag;
                        const ariaLabel = el.getAttribute('aria-label') || '';
                        const text = (el.innerText || el.textContent || '').trim()
                            .replace(/\s+/g, ' ').substring(0, 80);
                        const placeholder = el.getAttribute('placeholder') || '';
                        const name = (ariaLabel || text || placeholder).substring(0, 80);
                        if (!name || seen.has(name)) return;
                        seen.add(name);
                        const value = (tag === 'input' || tag === 'textarea')
                            ? (el.value || '').substring(0, 40) : '';
                        items.push(value ? role + ' "' + name + '" [' + value + ']' : role + ' "' + name + '"');
                    });
                    return items.join('\n');
                }
            """) as? String ?: ""
        } catch (e: Exception) {
            ""
        }
    }

    companion object {
        const val VIEWPORT_WIDTH = 1280
        const val VIEWPORT_HEIGHT = 800
    }
}

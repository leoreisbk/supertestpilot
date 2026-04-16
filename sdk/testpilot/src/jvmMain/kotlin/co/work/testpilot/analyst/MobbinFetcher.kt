package co.work.testpilot.analyst

import com.microsoft.playwright.Browser
import com.microsoft.playwright.Page
import com.microsoft.playwright.Playwright
import java.io.File
import java.nio.file.Path

class MobbinFetcher {

    companion object {
        private const val MOBBIN_SESSION_PATH = ".testpilot/sessions/mobbin.com.json"

        fun sessionFile(): File =
            File(System.getProperty("user.home"), MOBBIN_SESSION_PATH)
    }

    /** Returns true if a Mobbin session file exists. */
    fun hasSession(): Boolean = sessionFile().exists()

    /**
     * Uses Playwright to navigate to the Mobbin flow URL and screenshot each screen.
     * This bypasses the private API entirely — relies only on the saved session cookies.
     */
    fun fetchFlowScreenshots(flowUrl: String): List<ByteArray> {
        Playwright.create().use { playwright ->
            val browser = playwright.chromium().launch(launchOptions(headless = true))
            val context = browser.newContext(
                Browser.NewContextOptions()
                    .setStorageStatePath(Path.of(sessionFile().path))
                    .setViewportSize(1280, 900)
            )
            val page = context.newPage()

            // Navigate — use DOMCONTENTLOADED; Mobbin has persistent WS connections
            // that prevent NETWORKIDLE from ever firing.
            page.navigate(flowUrl, Page.NavigateOptions().setTimeout(60_000.0))
            page.waitForLoadState(
                com.microsoft.playwright.options.LoadState.DOMCONTENTLOADED,
                Page.WaitForLoadStateOptions().setTimeout(60_000.0)
            )

            // Give React time to render the screen grid
            page.waitForTimeout(3000.0)

            // Scroll to trigger lazy-loaded images
            scrollToBottom(page)

            // Find all screen image elements — Mobbin renders screens as <img> inside cards
            val screenshots = mutableListOf<ByteArray>()
            val imgHandles = page.querySelectorAll("img[src*='storage'], img[src*='supabase'], img[src*='mobbin'], img[src*='cloudfront']")

            if (imgHandles.isEmpty()) {
                // Fallback: screenshot each visible card element
                val cards = page.querySelectorAll("[data-testid='screen-card'], [class*='ScreenCard'], [class*='screen-card'], [class*='flow-card']")
                for (card in cards) {
                    runCatching {
                        card.scrollIntoViewIfNeeded()
                        page.waitForTimeout(200.0)
                        screenshots.add(card.screenshot())
                    }
                }
            } else {
                for (img in imgHandles) {
                    runCatching {
                        img.scrollIntoViewIfNeeded()
                        page.waitForTimeout(200.0)
                        screenshots.add(img.screenshot())
                    }
                }
            }

            if (screenshots.isEmpty()) {
                // Last resort: full-page screenshot
                scrollToTop(page)
                val fullPage = page.screenshot(Page.ScreenshotOptions().setFullPage(true))
                screenshots.add(fullPage)
            }

            return screenshots
        }
    }

    private fun scrollToBottom(page: Page) {
        page.evaluate("""
            () => new Promise(resolve => {
                let last = 0;
                const timer = setInterval(() => {
                    window.scrollBy(0, 800);
                    if (document.body.scrollHeight === last) {
                        clearInterval(timer);
                        resolve();
                    }
                    last = document.body.scrollHeight;
                }, 300);
            })
        """)
        page.waitForTimeout(1000.0)
    }

    private fun scrollToTop(page: Page) {
        page.evaluate("() => window.scrollTo(0, 0)")
        page.waitForTimeout(500.0)
    }
}

/** Extracts the full URL to pass to fetchFlowScreenshots — kept for interface compatibility. */
fun extractFlowId(url: String): String = url  // now we pass the full URL through

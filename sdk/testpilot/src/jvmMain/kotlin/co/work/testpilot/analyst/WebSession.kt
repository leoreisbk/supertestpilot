package co.work.testpilot.analyst

import com.microsoft.playwright.Browser
import com.microsoft.playwright.BrowserContext
import com.microsoft.playwright.BrowserType
import com.microsoft.playwright.Playwright
import java.io.File
import java.net.URI
import java.nio.file.Path

object WebSession {

    fun sessionPath(url: String): String {
        val hostname = java.net.URI(url).host?.takeIf { it.isNotEmpty() }
            ?: throw IllegalArgumentException("Cannot determine hostname from URL: $url")
        val home = System.getProperty("user.home")
        return "$home/.testpilot/sessions/$hostname.json"
    }

    /** Creates a context with the saved session loaded (if present), at 1280×800. */
    fun loadContext(browser: Browser, url: String): BrowserContext {
        val path = sessionPath(url)
        val opts = Browser.NewContextOptions().setViewportSize(
            AnalystDriverWeb.VIEWPORT_WIDTH, AnalystDriverWeb.VIEWPORT_HEIGHT
        )
        return if (File(path).exists()) {
            browser.newContext(opts.setStorageStatePath(Path.of(path)))
        } else {
            browser.newContext(opts)
        }
    }

    /** Persists the current context's cookies + localStorage to the session file. */
    fun saveSession(context: BrowserContext, url: String) {
        val path = sessionPath(url)
        File(path).parentFile?.mkdirs()
        context.storageState(BrowserContext.StorageStateOptions().setPath(Path.of(path)))
    }

    /**
     * Opens a headed browser for manual login.
     * Emits TESTPILOT_LOGIN_READY to stdout once the page loads.
     * Blocks until a newline arrives on stdin (CLI: Enter; macOS app: writes "\n").
     * Saves session and emits TESTPILOT_LOGIN_DONE:<path>.
     */
    fun interactiveLogin(url: String) {
        Playwright.create().use { playwright ->
            val browser = playwright.chromium().launch(BrowserType.LaunchOptions().setHeadless(false))
            val context = browser.newContext(
                Browser.NewContextOptions().setViewportSize(
                    AnalystDriverWeb.VIEWPORT_WIDTH, AnalystDriverWeb.VIEWPORT_HEIGHT
                )
            )
            val page = context.newPage()
            page.navigate(url)

            println("TESTPILOT_LOGIN_READY")
            System.out.flush()
            readLine() // blocks until '\n'

            val path = sessionPath(url)
            saveSession(context, url)

            println("TESTPILOT_LOGIN_DONE:$path")
            System.out.flush()
        }
    }
}

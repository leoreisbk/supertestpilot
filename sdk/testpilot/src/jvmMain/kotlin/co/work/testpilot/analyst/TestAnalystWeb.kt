package co.work.testpilot.analyst

import co.work.testpilot.ai.CachingAIClientJvm
import co.work.testpilot.runtime.Config
import co.work.testpilot.runtime.ConfigBuilder
import com.microsoft.playwright.BrowserType
import com.microsoft.playwright.Playwright
import io.ktor.client.*
import io.ktor.client.engine.cio.*
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class TestAnalystWeb(private val config: Config) {

    suspend fun run(
        url: String,
        objective: String,
        username: String? = null,
        password: String? = null,
    ): TestResult {
        val playwright = withContext(Dispatchers.IO) { Playwright.create() }
        val httpClient = HttpClient(CIO)

        try {
            val sessionExists = File(WebSession.sessionPath(url)).exists()

            // Auto-login: use a headed browser so the login form is visible
            if (username != null && password != null && !sessionExists) {
                val loginBrowser = withContext(Dispatchers.IO) {
                    playwright.chromium()
                        .launch(BrowserType.LaunchOptions().setHeadless(false))
                }
                try {
                    val loginContext = withContext(Dispatchers.IO) {
                        loginBrowser.newContext(
                            com.microsoft.playwright.Browser.NewContextOptions()
                                .setViewportSize(AnalystDriverWeb.VIEWPORT_WIDTH, AnalystDriverWeb.VIEWPORT_HEIGHT)
                        )
                    }
                    try {
                        val loginPage = withContext(Dispatchers.IO) { loginContext.newPage() }
                        withContext(Dispatchers.IO) { loginPage.navigate(url) }
                        val loginConfig = ConfigBuilder()
                            .provider(config.provider)
                            .apiKey(config.apiKey)
                            .maxSteps(5)
                            .language(config.language)
                            .build()
                        Analyst(AnalystDriverWeb(loginPage), buildWebAIClient(loginConfig, httpClient), loginConfig)
                            .run("Log in with username: $username and password: $password")
                        WebSession.saveSession(loginContext, url)
                    } finally {
                        withContext(Dispatchers.IO) { loginContext.close() }
                    }
                } finally {
                    withContext(Dispatchers.IO) { loginBrowser.close() }
                }
            }

            // Test run: headless
            val browser = withContext(Dispatchers.IO) {
                playwright.chromium().launch(BrowserType.LaunchOptions().setHeadless(true))
            }
            val context = WebSession.loadContext(browser, url)
            try {
                val page = withContext(Dispatchers.IO) { context.newPage() }
                withContext(Dispatchers.IO) { page.navigate(url) }

                val cacheDir = "${System.getProperty("user.home")}/.testpilot/cache"
                val lastResponseCached = java.util.concurrent.atomic.AtomicBoolean(false)
                val aiClient = CachingAIClientJvm(
                    delegate = buildWebAIClient(config, httpClient),
                    cacheDir = cacheDir,
                    onCacheHit = { lastResponseCached.set(true) },
                )

                val result = TestAnalyst(AnalystDriverWeb(page), aiClient, config).run(objective) { message ->
                    val prefix = if (lastResponseCached.getAndSet(false)) "(cached) " else ""
                    println("TESTPILOT_STEP: $prefix$message")
                    System.out.flush()
                }

                val verdict = if (result.passed) "PASS" else "FAIL"
                println("TESTPILOT_RESULT: $verdict ${result.reason}")
                System.out.flush()

                return result
            } finally {
                withContext(Dispatchers.IO) {
                    context.close()
                    browser.close()
                }
            }
        } finally {
            withContext(Dispatchers.IO) { playwright.close() }
            httpClient.close()
        }
    }

}

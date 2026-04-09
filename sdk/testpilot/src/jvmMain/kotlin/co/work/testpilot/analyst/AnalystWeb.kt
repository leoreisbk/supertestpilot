package co.work.testpilot.analyst

import co.work.testpilot.runtime.Config
import co.work.testpilot.runtime.ConfigBuilder
import com.microsoft.playwright.BrowserType
import com.microsoft.playwright.Playwright
import io.ktor.client.*
import io.ktor.client.engine.cio.*
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AnalystWeb(private val config: Config) {

    suspend fun run(
        url: String,
        objective: String,
        outputPath: String,
        username: String? = null,
        password: String? = null,
    ): String {
        val playwright = withContext(Dispatchers.IO) { Playwright.create() }
        val browser = withContext(Dispatchers.IO) {
            playwright.chromium().launch(BrowserType.LaunchOptions().setHeadless(false))
        }
        val httpClient = HttpClient(CIO)

        try {
            val sessionExists = File(WebSession.sessionPath(url)).exists()

            // Auto-login pre-step: runs Analyst with maxSteps=5 to fill in credentials
            if (username != null && password != null && !sessionExists) {
                val loginContext = withContext(Dispatchers.IO) {
                    browser.newContext(
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
            }

            val context = WebSession.loadContext(browser, url)
            val page = withContext(Dispatchers.IO) { context.newPage() }
            withContext(Dispatchers.IO) { page.navigate(url) }

            val report = Analyst(AnalystDriverWeb(page), buildWebAIClient(config, httpClient), config)
                .run(objective) { observation ->
                    println("TESTPILOT_STEP: $observation")
                    System.out.flush()
                }
            val html = HtmlReportWriter.generate(report, config.language)

            val file = File(outputPath).also { it.parentFile?.mkdirs() }
            file.writeText(html)
            println("TESTPILOT_REPORT_PATH=${file.absolutePath}")
            System.out.flush()
            return file.absolutePath
        } finally {
            withContext(Dispatchers.IO) {
                browser.close()
                playwright.close()
            }
            httpClient.close()
        }
    }

}

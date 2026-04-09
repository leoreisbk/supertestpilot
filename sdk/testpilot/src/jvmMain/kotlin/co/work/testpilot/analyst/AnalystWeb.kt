package co.work.testpilot.analyst

import co.work.testpilot.ai.AnthropicChatClient
import co.work.testpilot.ai.OpenAIChatClient
import co.work.testpilot.runtime.AIProvider
import co.work.testpilot.runtime.AIProviderDefaults
import co.work.testpilot.runtime.Config
import co.work.testpilot.runtime.ConfigBuilder
import com.aallam.openai.api.logging.LogLevel
import com.aallam.openai.client.OpenAI
import com.aallam.openai.client.OpenAIConfig
import com.aallam.openai.client.OpenAIHost
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
                    Analyst(AnalystDriverWeb(loginPage), buildAIClient(loginConfig, httpClient), loginConfig)
                        .run("Log in with username: $username and password: $password")
                    WebSession.saveSession(loginContext, url)
                } finally {
                    withContext(Dispatchers.IO) { loginContext.close() }
                }
            }

            val context = WebSession.loadContext(browser, url)
            val page = withContext(Dispatchers.IO) { context.newPage() }
            withContext(Dispatchers.IO) { page.navigate(url) }

            val report = Analyst(AnalystDriverWeb(page), buildAIClient(config, httpClient), config)
                .run(objective)
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

    private fun buildAIClient(cfg: Config, httpClient: HttpClient) = when (cfg.provider) {
        AIProvider.Anthropic -> AnthropicChatClient(
            apiKey = cfg.apiKey,
            modelId = cfg.modelId ?: AIProviderDefaults.anthropicModel,
            httpClient = httpClient,
            apiHost = cfg.apiHost ?: "https://api.anthropic.com",
            extraHeaders = cfg.apiHeaders,
        )
        AIProvider.OpenAI -> OpenAIChatClient(
            openAI = OpenAI(config = OpenAIConfig(
                token = cfg.apiKey,
                organization = cfg.apiOrg,
                headers = cfg.apiHeaders,
                host = cfg.apiHost?.let { OpenAIHost(it) } ?: OpenAIHost.OpenAI,
                logLevel = LogLevel.None,
            )),
            modelId = cfg.modelId ?: AIProviderDefaults.openAIModel,
            httpClient = httpClient,
            apiKey = cfg.apiKey,
            apiHost = cfg.apiHost ?: "https://api.openai.com",
        )
        AIProvider.Gemini ->
            throw IllegalArgumentException("Gemini is not supported on web platform. Use anthropic or openai.")
    }
}

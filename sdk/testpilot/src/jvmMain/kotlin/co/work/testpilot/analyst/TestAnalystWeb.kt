package co.work.testpilot.analyst

import co.work.testpilot.ai.AnthropicChatClient
import co.work.testpilot.ai.CachingAIClientJvm
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
                        Analyst(AnalystDriverWeb(loginPage), buildAIClient(loginConfig, httpClient), loginConfig)
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
            try {
                val context = WebSession.loadContext(browser, url)
                val page = withContext(Dispatchers.IO) { context.newPage() }
                withContext(Dispatchers.IO) { page.navigate(url) }

                val cacheDir = "${System.getProperty("user.home")}/.testpilot/cache"
                var lastResponseCached = false
                val aiClient = CachingAIClientJvm(
                    delegate = buildAIClient(config, httpClient),
                    cacheDir = cacheDir,
                    onCacheHit = { lastResponseCached = true },
                )

                val result = TestAnalyst(AnalystDriverWeb(page), aiClient, config).run(objective) { message ->
                    val prefix = if (lastResponseCached) "(cached) " else ""
                    println("TESTPILOT_STEP: $prefix$message")
                    System.out.flush()
                    lastResponseCached = false
                }

                val verdict = if (result.passed) "PASS" else "FAIL"
                println("TESTPILOT_RESULT: $verdict ${result.reason}")
                System.out.flush()

                return result
            } finally {
                withContext(Dispatchers.IO) { browser.close() }
            }
        } finally {
            withContext(Dispatchers.IO) { playwright.close() }
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

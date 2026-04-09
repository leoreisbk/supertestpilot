package co.work.testpilot.analyst

import co.work.testpilot.ai.AnthropicChatClient
import co.work.testpilot.ai.CachingAIClient
import co.work.testpilot.ai.GeminiChatClient
import co.work.testpilot.ai.OpenAIChatClient
import co.work.testpilot.runtime.AIProvider
import co.work.testpilot.runtime.AIProviderDefaults
import co.work.testpilot.runtime.Config
import com.aallam.openai.api.logging.LogLevel
import com.aallam.openai.client.OpenAI
import com.aallam.openai.client.OpenAIConfig
import com.aallam.openai.client.OpenAIHost
import io.ktor.client.*
import io.ktor.client.engine.darwin.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import platform.Foundation.NSCachesDirectory
import platform.Foundation.NSSearchPathForDirectoriesInDomains
import platform.Foundation.NSUserDomainMask
import platform.XCTest.XCUIApplication

class TestAnalystIOS(private val config: Config) {

    suspend fun run(objective: String, xcApp: XCUIApplication, username: String? = null, password: String? = null): TestResult {
        withContext(Dispatchers.Main) { xcApp.activate() }
        delay(5000)

        val httpClient = HttpClient(Darwin)
        val baseClient = when (config.provider) {
            AIProvider.Anthropic -> AnthropicChatClient(
                apiKey = config.apiKey,
                modelId = config.modelId ?: AIProviderDefaults.anthropicModel,
                httpClient = httpClient,
                apiHost = config.apiHost ?: "https://api.anthropic.com",
                extraHeaders = config.apiHeaders,
            )
            AIProvider.Gemini -> GeminiChatClient(
                apiKey = config.apiKey,
                modelId = config.modelId ?: AIProviderDefaults.geminiModel,
                httpClient = httpClient,
                apiHost = config.apiHost ?: "https://generativelanguage.googleapis.com",
            )
            AIProvider.OpenAI -> OpenAIChatClient(
                openAI = OpenAI(
                    config = OpenAIConfig(
                        token = config.apiKey,
                        organization = config.apiOrg,
                        headers = config.apiHeaders,
                        host = config.apiHost?.let { OpenAIHost(it) } ?: OpenAIHost.OpenAI,
                        logLevel = LogLevel.None,
                    )
                ),
                modelId = config.modelId ?: AIProviderDefaults.openAIModel,
                httpClient = httpClient,
                apiKey = config.apiKey,
                apiHost = config.apiHost ?: "https://api.openai.com",
            )
        }

        val cacheDir = (NSSearchPathForDirectoriesInDomains(
            NSCachesDirectory, NSUserDomainMask, true
        ).firstOrNull() as? String ?: "/tmp") + "/testpilot-cache"

        var lastResponseCached = false
        val aiClient = CachingAIClient(
            delegate = baseClient,
            cacheDir = cacheDir,
            onCacheHit = { lastResponseCached = true },
        )

        val driver = AnalystDriverIOS(xcApp)

        if (!username.isNullOrEmpty() && !password.isNullOrEmpty()) {
            val loginConfig = config.copy(maxSteps = 5)
            Analyst(driver, baseClient, loginConfig).run("Log in with username: $username and password: $password")
        }

        val analyst = TestAnalyst(driver, aiClient, config)

        val result = analyst.run(objective) { message ->
            val prefix = if (lastResponseCached) "(cached) " else ""
            println("TESTPILOT_STEP: $prefix$message")
            lastResponseCached = false
        }

        val verdict = if (result.passed) "PASS" else "FAIL"
        println("TESTPILOT_RESULT: $verdict ${result.reason}")

        return result
    }
}

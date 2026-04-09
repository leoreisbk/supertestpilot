package co.work.testpilot.analyst

import co.work.testpilot.ai.AnthropicChatClient
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
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import platform.Foundation.NSData
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.NSDocumentDirectory
import platform.Foundation.NSSearchPathForDirectoriesInDomains
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUserDomainMask
import platform.Foundation.dataUsingEncoding
import platform.Foundation.writeToFile
import platform.XCTest.XCUIApplication

class AnalystIOS(private val config: Config) {

    // Primary entry point: accepts a pre-created XCUIApplication.
    // Callers should create XCUIApplication outside the async test function body (e.g. in setUp())
    // to avoid the XCTWaiter stack assertion introduced in Xcode 26 where
    // XCUIApplication(bundleIdentifier:) internally calls XCUIWaitAndAssert, conflicting with
    // the async test runner's outer waiter.
    suspend fun run(objective: String, xcApp: XCUIApplication, username: String? = null, password: String? = null): String {
        withContext(Dispatchers.Main) { xcApp.activate() }
        delay(5000) // wait for app to fully load before first screenshot

        val httpClient = HttpClient(Darwin)
        val aiClient = when (config.provider) {
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

        val driver = AnalystDriverIOS(xcApp)

        if (!username.isNullOrEmpty() && !password.isNullOrEmpty()) {
            val loginConfig = config.copy(maxSteps = 5)
            Analyst(driver, aiClient, loginConfig).run("Log in with username: $username and password: $password")
        }

        val analyst = Analyst(driver, aiClient, config)
        val report = analyst.run(objective)
        val html = HtmlReportWriter.generate(report, config.language)

        // Emit the report inline so the CLI can extract it from xcodebuild stdout
        // without needing devicectl file transfer (which is unreliable on physical devices).
        println("TESTPILOT_REPORT_START")
        println(html)
        println("TESTPILOT_REPORT_END")

        val docsDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true)
            .firstOrNull() as? String ?: NSTemporaryDirectory()
        val reportPath = "$docsDir/testpilot_report.html"
        @OptIn(ExperimentalForeignApi::class)
        val data: NSData? = (html as NSString).dataUsingEncoding(NSUTF8StringEncoding)
        data?.writeToFile(path = reportPath, atomically = true)

        println("TESTPILOT_REPORT_PATH=$reportPath")
        return reportPath
    }

    // Convenience overload: creates XCUIApplication internally.
    // Avoid calling this from an async throws XCTest function on Xcode 26+ — use the
    // run(objective:xcApp:) overload and create XCUIApplication in setUp() instead.
    suspend fun run(objective: String, bundleId: String? = null, username: String? = null, password: String? = null): String {
        val xcApp = if (bundleId != null) XCUIApplication(bundleId) else XCUIApplication()
        return run(objective, xcApp, username, password)
    }
}

package co.work.testpilot.analyst

import co.work.testpilot.ai.AnthropicChatClient
import co.work.testpilot.ai.OpenAIChatClient
import co.work.testpilot.runtime.AIProvider
import co.work.testpilot.runtime.AIProviderDefaults
import co.work.testpilot.runtime.Config
import com.aallam.openai.api.logging.LogLevel
import com.aallam.openai.client.OpenAI
import com.aallam.openai.client.OpenAIConfig
import com.aallam.openai.client.OpenAIHost
import io.ktor.client.*
import io.ktor.client.engine.cio.*
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File

class AnalystAndroid(private val config: Config) {

    private val httpClient = HttpClient(CIO)

    suspend fun run(objective: String): String {
        val aiClient = when (config.provider) {
            AIProvider.Anthropic -> AnthropicChatClient(
                apiKey = config.apiKey,
                modelId = config.modelId ?: AIProviderDefaults.anthropicModel,
                httpClient = httpClient,
                apiHost = config.apiHost ?: "https://api.anthropic.com",
                extraHeaders = config.apiHeaders,
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

        val driver = AnalystDriverAndroid()

        val args = InstrumentationRegistry.getArguments()
        val username = args.getString("TESTPILOT_USERNAME")?.takeIf { it.isNotEmpty() }
        val password = args.getString("TESTPILOT_PASSWORD")?.takeIf { it.isNotEmpty() }
        if (username != null && password != null) {
            val loginConfig = config.copy(maxSteps = 5)
            Analyst(driver, aiClient, loginConfig).run("Log in with username: $username and password: $password")
        }

        val analyst = Analyst(driver, aiClient, config)
        val report = analyst.run(objective)
        val html = HtmlReportWriter.generate(report)

        val reportDir = InstrumentationRegistry.getInstrumentation().targetContext
            .getExternalFilesDir(null)
            ?: throw IllegalStateException("External files dir not available")
        val reportFile = java.io.File(reportDir, "testpilot_report.html")
        reportFile.writeText(html)
        val reportPath = reportFile.absolutePath

        println("TESTPILOT_REPORT_PATH=${reportFile.absolutePath}")
        return reportFile.absolutePath
    }
}

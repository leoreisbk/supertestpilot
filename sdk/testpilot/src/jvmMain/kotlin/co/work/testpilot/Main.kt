package co.work.testpilot

import co.work.testpilot.analyst.AnalystWeb
import co.work.testpilot.analyst.TestAnalystWeb
import co.work.testpilot.analyst.WebSession
import co.work.testpilot.runtime.AIProvider
import co.work.testpilot.runtime.ConfigBuilder
import kotlinx.coroutines.runBlocking
import kotlin.system.exitProcess

fun main() = runBlocking {
    fun env(name: String): String? = System.getenv(name)
    fun requireEnv(name: String): String = env(name) ?: run {
        System.err.println("Error: environment variable $name is required")
        exitProcess(1)
    }

    val mode = requireEnv("TESTPILOT_MODE")
    val url  = requireEnv("TESTPILOT_WEB_URL")

    when (mode) {
        "login" -> {
            WebSession.interactiveLogin(url)
        }

        "analyze", "test" -> {
            val apiKey    = requireEnv("TESTPILOT_API_KEY")
            val provider  = env("TESTPILOT_PROVIDER") ?: "anthropic"
            if (provider == "gemini") {
                System.err.println("Error: Gemini is not supported on the web platform. Use 'anthropic' or 'openai'.")
                exitProcess(1)
            }
            val maxSteps  = env("TESTPILOT_MAX_STEPS")?.toIntOrNull() ?: 20
            val lang      = env("TESTPILOT_LANG") ?: "en"
            val objective = requireEnv("TESTPILOT_OBJECTIVE")
            val username  = env("TESTPILOT_WEB_USERNAME")?.takeIf { it.isNotEmpty() }
            val password  = env("TESTPILOT_WEB_PASSWORD")?.takeIf { it.isNotEmpty() }

            val config = ConfigBuilder()
                .provider(when (provider) {
                    "openai" -> AIProvider.OpenAI
                    "gemini" -> AIProvider.Gemini
                    else     -> AIProvider.Anthropic
                })
                .apiKey(apiKey)
                .maxSteps(maxSteps)
                .language(lang)
                .build()

            if (mode == "analyze") {
                val output = env("TESTPILOT_OUTPUT") ?: "./report.html"
                AnalystWeb(config).run(url, objective, output, username, password)
            } else {
                val result = TestAnalystWeb(config).run(url, objective, username, password)
                if (!result.passed) exitProcess(1)
            }
        }

        else -> {
            System.err.println("Error: unknown TESTPILOT_MODE '$mode'. Use analyze, test, or login.")
            exitProcess(1)
        }
    }
}

package co.work.testpilot

import co.work.testpilot.analyst.AnalystWeb
import co.work.testpilot.analyst.HtmlReportWriter
import co.work.testpilot.analyst.MobbinAnalyst
import co.work.testpilot.analyst.MobbinFetcher
import co.work.testpilot.analyst.TestAnalystWeb
import co.work.testpilot.analyst.WebSession
import co.work.testpilot.analyst.buildWebAIClient
import co.work.testpilot.runtime.AIProvider
import co.work.testpilot.runtime.ConfigBuilder
import io.ktor.client.*
import io.ktor.client.engine.cio.*
import kotlinx.coroutines.runBlocking
import java.io.File
import kotlin.system.exitProcess

fun main(args: Array<String>) {
    runBlocking {
        fun env(name: String): String? = System.getenv(name)
        fun requireEnv(name: String): String = env(name) ?: run {
            System.err.println("Error: environment variable $name is required")
            exitProcess(1)
        }

        val mode = requireEnv("TESTPILOT_MODE")

        when (mode) {
            "login" -> {
                val url = requireEnv("TESTPILOT_WEB_URL")
                WebSession.interactiveLogin(url)
            }

            "mobbin-login" -> {
                WebSession.interactiveLogin("https://mobbin.com")
            }

            "analyze", "test" -> {
                val url       = requireEnv("TESTPILOT_WEB_URL")
                val apiKey    = requireEnv("TESTPILOT_API_KEY")
                val provider  = env("TESTPILOT_PROVIDER") ?: "anthropic"
                val maxSteps  = env("TESTPILOT_MAX_STEPS")?.toIntOrNull() ?: 40
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

            "research" -> {
                val apiKey    = requireEnv("TESTPILOT_API_KEY")
                val provider  = env("TESTPILOT_PROVIDER") ?: "anthropic"
                val maxSteps  = env("TESTPILOT_MAX_STEPS")?.toIntOrNull() ?: 40
                val lang      = env("TESTPILOT_LANG") ?: "en"
                val output    = env("TESTPILOT_OUTPUT") ?: "./report.html"
                val persona   = env("TESTPILOT_PERSONA")?.takeIf { it.isNotEmpty() }
                val objective = env("TESTPILOT_OBJECTIVE")
                    ?.takeIf { it.isNotEmpty() }
                    ?: if (persona != null) "Analyze this app from the perspective of the persona." else {
                        System.err.println("Error: TESTPILOT_OBJECTIVE is required for research mode")
                        exitProcess(1)
                    }

                val flowUrl  = env("TESTPILOT_MOBBIN_FLOW_URL")
                val appName  = env("TESTPILOT_MOBBIN_APP")
                val flowName = env("TESTPILOT_MOBBIN_FLOW_NAME")

                val fetcher = MobbinFetcher()

                if (!fetcher.hasSession()) {
                    System.err.println("Error: Mobbin session not found — run: testpilot mobbin-login")
                    exitProcess(1)
                }

                if (flowUrl.isNullOrEmpty() && (appName.isNullOrEmpty() || flowName.isNullOrEmpty())) {
                    System.err.println("Error: either TESTPILOT_MOBBIN_FLOW_URL or both TESTPILOT_MOBBIN_APP and TESTPILOT_MOBBIN_FLOW_NAME are required")
                    exitProcess(1)
                }

                val images = try {
                    if (!flowUrl.isNullOrEmpty()) {
                        println("TESTPILOT_STEP: Opening Mobbin flow in browser…")
                        System.out.flush()
                        fetcher.fetchFlowScreenshots(flowUrl)
                    } else {
                        println("TESTPILOT_STEP: Searching Mobbin for ${appName}…")
                        System.out.flush()
                        fetcher.fetchByAppName(appName!!, flowName)
                    }
                } catch (e: Exception) {
                    System.err.println("Error fetching Mobbin flow: ${e.message}")
                    exitProcess(1)
                }

                val config = ConfigBuilder()
                    .provider(when (provider) {
                        "openai" -> AIProvider.OpenAI
                        "gemini" -> AIProvider.Gemini
                        else     -> AIProvider.Anthropic
                    })
                    .apiKey(apiKey)
                    .maxSteps(maxSteps)
                    .language(lang)
                    .apply { if (persona != null) persona(persona) }
                    .build()

                val aiClient = HttpClient(CIO)
                try {
                    val report = MobbinAnalyst(buildWebAIClient(config, aiClient), config)
                        .run(images, objective) { obs ->
                            println("TESTPILOT_STEP: $obs")
                            System.out.flush()
                        }

                    val html = HtmlReportWriter.generate(report, lang)
                    val file = File(output).also { it.parentFile?.mkdirs() }
                    file.writeText(html)
                    println("TESTPILOT_REPORT_PATH=${file.absolutePath}")
                    System.out.flush()
                } finally {
                    aiClient.close()
                }
            }

            else -> {
                System.err.println("Error: unknown TESTPILOT_MODE '$mode'. Use analyze, test, login, mobbin-login, or research.")
                exitProcess(1)
            }
        }
    }
}

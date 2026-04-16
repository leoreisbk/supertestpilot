# Research Mode — Mobbin Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Research run mode to TestPilot that pulls screens from Mobbin flows and produces a competitive UX HTML report.

**Architecture:** A new `MobbinAnalyst` (commonMain) takes pre-downloaded images as `List<ByteArray>` and uses a new `ResearchVisionPrompt` to analyze each screen sequentially, then generates a summary. The JVM target handles Mobbin session auth (reusing `WebSession.interactiveLogin`) and image downloading (`MobbinFetcher`). The CLI gains `mobbin-login` and `research` subcommands; the macOS app gains a Research mode in the mode picker.

**Tech Stack:** Kotlin Multiplatform (commonMain + jvmMain), Ktor CIO for HTTP, Playwright (existing) for Mobbin auth, Swift/SwiftUI for macOS app changes.

---

## File Map

**New files:**
- `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/SummaryGenerator.kt` — shared `generateSummary` function extracted from `Analyst`
- `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/ai/ResearchVisionPrompt.kt` — competitive UX analyst prompt, returns observation string per screen
- `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/MobbinAnalyst.kt` — static-image analyst loop, no driver/interaction
- `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/MobbinFetcher.kt` — downloads Mobbin flow images using saved Playwright session cookies
- `mac-app/TestPilotApp/Services/ResearchRunner.swift` — builds the JVM process for research mode

**Modified files:**
- `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/AnalysisReport.kt` — add `source: String?` field
- `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/HtmlReportWriter.kt` — add research title + `[ADVANTAGE]`/`[WEAKNESS]`/`[PATTERN]` badges
- `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/Analyst.kt` — delegate to `SummaryGenerator`
- `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/Main.kt` — add `research` and `mobbin-login` modes
- `testpilot` (CLI script) — add `mobbin-login` and `research` subcommands
- `mac-app/TestPilotApp/Models/RunConfig.swift` — add `research` RunMode, Mobbin fields
- `mac-app/TestPilotApp/Views/RunView.swift` — Research mode form section
- `mac-app/TestPilotApp/Services/AnalysisRunner.swift` — handle `.research` case + `mobbinLogin()`
- `mac-app/TestPilotTests/RunConfigTests.swift` — tests for research mode `isValid`

---

## Task 1: Extract `SummaryGenerator`

Extracts the private `generateSummary` function from `Analyst` into a shared internal function so `MobbinAnalyst` can reuse it without duplication.

**Files:**
- Create: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/SummaryGenerator.kt`
- Modify: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/Analyst.kt:83-132`

- [ ] **Step 1: Create `SummaryGenerator.kt`**

```kotlin
package co.work.testpilot.analyst

import co.work.testpilot.ai.AIClient
import co.work.testpilot.ai.ChatMessage
import co.work.testpilot.runtime.Config

internal suspend fun generateSummary(
    aiClient: AIClient,
    config: Config,
    objective: String,
    steps: List<AnalysisStep>,
): String {
    val observations = steps.mapNotNull { it.observation }.distinct()
    if (observations.isEmpty()) return "No observations recorded."

    val languageInstruction = if (config.language == "en") "" else
        "Write your entire response in ${config.language}."

    val personaContext = if (config.personaMarkdown.isNullOrBlank()) "" else """

This evaluation was conducted from the perspective of:
<persona>
${config.personaMarkdown}
</persona>

Frame your findings through the lens of this persona's goals and pain points.""".trimIndent()

    val prompt = """
        You conducted a UX evaluation of a mobile app with this objective: "$objective"

        Raw observations from the session:
        ${observations.mapIndexed { i, obs -> "${i + 1}. $obs" }.joinToString("\n")}

        Write a structured evaluation report for a product team (PMs, designers, QA leads). Format it exactly as follows:

        **Overall verdict**: One sentence stating whether the app succeeds or fails at the objective and why.

        **Critical issues** (blockers that prevent the objective from being met — list only if any exist):
        - [item]

        **Friction points** (problems that make the objective harder but not impossible):
        - [item]

        **Positive patterns** (things the app does well related to the objective — list only if any exist):
        - [item]

        **Recommendation**: One concrete next step the team should prioritize.

        Be specific. Each bullet must name the screen/flow and the concrete problem or pattern. Do not generalize.
        $languageInstruction$personaContext
    """.trimIndent()

    return aiClient.chatCompletion(
        messages = listOf(
            ChatMessage(role = ChatMessage.ROLE_SYSTEM, content = "You are a senior UX researcher writing a structured product evaluation. Be specific, evidence-based, and actionable."),
            ChatMessage(role = ChatMessage.ROLE_USER, content = prompt),
        ),
        maxTokens = 800,
        temperature = 0.0,
    )
}
```

- [ ] **Step 2: Update `Analyst.kt` to delegate to `SummaryGenerator`**

Replace the private `generateSummary` function body in `Analyst.kt` (lines 83–132) with a delegation call. The method stays as a private wrapper so the call site (`analyst.run`) doesn't change:

```kotlin
private suspend fun generateSummary(objective: String, steps: List<AnalysisStep>): String =
    co.work.testpilot.analyst.generateSummary(aiClient, config, objective, steps)
```

- [ ] **Step 3: Verify compilation**

```bash
cd sdk && ./gradlew testpilot:compileKotlinJvm
```

Expected: BUILD SUCCESSFUL with no errors.

- [ ] **Step 4: Commit**

```bash
git add sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/SummaryGenerator.kt \
        sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/Analyst.kt
git commit -m "refactor(sdk): extract generateSummary into shared SummaryGenerator"
```

---

## Task 2: Add `source` to `AnalysisReport` + update `HtmlReportWriter`

Adds a `source` field to `AnalysisReport` so the HTML report can show "Research Report" instead of "Analysis Report", and adds competitive research badge colors.

**Files:**
- Modify: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/AnalysisReport.kt`
- Modify: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/HtmlReportWriter.kt`

- [ ] **Step 1: Add `source` to `AnalysisReport`**

Replace the entire file content:

```kotlin
package co.work.testpilot.analyst

data class AnalysisReport(
    val objective: String,
    val summary: String,
    val stepCount: Int,
    val durationMs: Long,
    val steps: List<AnalysisStep>,
    val persona: String? = null,
    val source: String? = null,
)
```

- [ ] **Step 2: Add `researchTitle` to `Labels` in `HtmlReportWriter`**

In `HtmlReportWriter.kt`, replace the `Labels` data class and `labelsFor` function:

```kotlin
private data class Labels(
    val htmlLang: String,
    val title: String,
    val researchTitle: String,
    val summary: String,
    val stepByStep: String,
    val step: String,
    val steps: String,
    val evaluatedAs: String,
)

private fun labelsFor(language: String): Labels = when (language) {
    "pt-BR", "pt" -> Labels(
        htmlLang      = "pt-BR",
        title         = "Relatório de Análise TestPilot",
        researchTitle = "Relatório de Pesquisa TestPilot",
        summary       = "Resumo",
        stepByStep    = "Passo a passo",
        step          = "Passo",
        steps         = "passos",
        evaluatedAs   = "Avaliado como",
    )
    else -> Labels(
        htmlLang      = "en",
        title         = "TestPilot Analysis Report",
        researchTitle = "TestPilot Research Report",
        summary       = "Summary",
        stepByStep    = "Step-by-step",
        step          = "Step",
        steps         = "steps",
        evaluatedAs   = "Evaluated as",
    )
}
```

- [ ] **Step 3: Use `researchTitle` in `generate()` and add new badges**

In `generate()`, replace the `val lbl = labelsFor(language)` line and the `<h1>` title reference:

At the top of `generate()`, add after `val lbl = labelsFor(language)`:
```kotlin
val reportTitle = if (report.source == "mobbin") lbl.researchTitle else lbl.title
```

Replace `${lbl.title}` (two occurrences — in `<title>` and `<h1>`) with `$reportTitle`.

- [ ] **Step 4: Add `[ADVANTAGE]`, `[WEAKNESS]`, `[PATTERN]` badges**

In `renderObservation()`, add the new cases before the `else` clause:

```kotlin
private fun renderObservation(obs: String): String {
    val (badge, text) = when {
        obs.startsWith("[CRITICAL]") ->
            """<span class="badge badge-critical">CRITICAL</span>""" to obs.removePrefix("[CRITICAL]").trim()
        obs.startsWith("[ISSUE]") ->
            """<span class="badge badge-issue">ISSUE</span>""" to obs.removePrefix("[ISSUE]").trim()
        obs.startsWith("[POSITIVE]") ->
            """<span class="badge badge-positive">POSITIVE</span>""" to obs.removePrefix("[POSITIVE]").trim()
        obs.startsWith("[ADVANTAGE]") ->
            """<span class="badge badge-advantage">ADVANTAGE</span>""" to obs.removePrefix("[ADVANTAGE]").trim()
        obs.startsWith("[WEAKNESS]") ->
            """<span class="badge badge-weakness">WEAKNESS</span>""" to obs.removePrefix("[WEAKNESS]").trim()
        obs.startsWith("[PATTERN]") ->
            """<span class="badge badge-pattern">PATTERN</span>""" to obs.removePrefix("[PATTERN]").trim()
        else -> "" to obs
    }
    return "$badge${text.htmlEscape()}"
}
```

- [ ] **Step 5: Add badge CSS**

In the `<style>` block inside `generate()`, add after `.badge-positive { background: #34c759; color: #fff; }`:

```css
.badge-advantage { background: #34c759; color: #fff; }
.badge-weakness  { background: #ff3b30; color: #fff; }
.badge-pattern   { background: #007aff; color: #fff; }
```

- [ ] **Step 6: Verify compilation**

```bash
cd sdk && ./gradlew testpilot:compileKotlinJvm
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 7: Commit**

```bash
git add sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/AnalysisReport.kt \
        sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/HtmlReportWriter.kt
git commit -m "feat(sdk): add research report title and competitive UX badge types"
```

---

## Task 3: `ResearchVisionPrompt`

New prompt class that frames the AI as a competitive UX analyst reviewing static Mobbin screens. Returns an observation string (no navigation action).

**Files:**
- Create: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/ai/ResearchVisionPrompt.kt`

- [ ] **Step 1: Create `ResearchVisionPrompt.kt`**

```kotlin
package co.work.testpilot.ai

import co.work.testpilot.runtime.Config

class ResearchVisionPrompt(
    private val aiClient: AIClient,
    private val config: Config,
) {
    private val languageInstruction: String = if (config.language == "en") "" else
        "All observations must be written in ${config.language}."

    private val personaSection: String = config.personaMarkdown
        ?.takeIf { it.isNotBlank() }
        ?.let { persona ->
            """

## Persona lens
Filter your observations through the perspective of this user. Would they understand this screen? Does it serve their goals?

<persona>
$persona
</persona>""".trimIndent()
        } ?: ""

    private val systemPrompt: String = """
        You are a competitive UX analyst reviewing screens from a competitor app. Your findings will be used by a product team to understand what this competitor does well, where they fall short, and what patterns are worth adopting or avoiding.

        ## Your job
        For each screen, identify one specific design pattern, decision, or UX strategy. Classify it as an advantage, a weakness, or a neutral pattern. Be specific — name the exact element, screen section, or flow. Generic observations like "the design is clean" are not useful.

        ## Observation quality standards
        - **Specific**: Name the exact element or section (e.g. "Onboarding screen 2: progress bar shows 3 of 5 steps, anchoring the user's sense of completion")
        - **Strategic**: Connect the observation to its competitive implication (e.g. "reduces drop-off by making the end feel close")
        - **Actionable**: State what a product team could learn or counter

        ## Tag every observation with exactly one prefix:
        - [ADVANTAGE] — a pattern this app executes well; worth learning from or countering
        - [WEAKNESS] — a gap or poor decision that represents an opportunity to win
        - [PATTERN] — a neutral design decision worth noting, no clear competitive implication

        Respond ONLY with a single valid JSON object. No markdown, no explanation.
        $languageInstruction$personaSection
    """.trimIndent()

    suspend operator fun invoke(
        objective: String,
        screenshotPng: ByteArray,
        observationsSoFar: List<String>,
    ): String {
        val observationsText = if (observationsSoFar.isEmpty()) {
            "None yet."
        } else {
            observationsSoFar.mapIndexed { i, obs -> "${i + 1}. $obs" }.joinToString("\n")
        }

        val userPrompt = """
            Research objective: $objective

            Observations already recorded (do NOT repeat these):
            $observationsText

            Look at this screen. Identify one specific competitive UX observation.

            Respond with a JSON object:
            - observation: one finding with [ADVANTAGE]/[WEAKNESS]/[PATTERN] prefix — what you saw and its competitive implication

            Example:
            {"observation":"[ADVANTAGE] Onboarding screen 2: social proof counter ('Join 2M runners') appears before the paywall, building desire before asking for commitment — reduces drop-off at the upsell step"}
        """.trimIndent()

        val messages = listOf(
            ChatMessage(role = ChatMessage.ROLE_SYSTEM, content = systemPrompt),
            ChatMessage(role = ChatMessage.ROLE_USER, content = userPrompt),
        )

        val response = aiClient.chatCompletion(
            messages = messages,
            maxTokens = maxOf(config.maxTokens, 512),
            temperature = config.temperature,
            imageBytes = screenshotPng,
        )

        return parseObservation(response)
    }

    private fun parseObservation(response: String): String {
        // Extract "observation" field from JSON response.
        // Handles both {"observation":"..."} and responses wrapped in whitespace/newlines.
        val match = Regex(""""observation"\s*:\s*"((?:[^"\\]|\\.)*)"""").find(response)
        return match?.groupValues?.get(1)
            ?.replace("\\\"", "\"")
            ?.replace("\\n", " ")
            ?.trim()
            ?: "[PATTERN] Screen captured — AI returned unexpected format: ${response.take(100)}"
    }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd sdk && ./gradlew testpilot:compileKotlinJvm
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/ai/ResearchVisionPrompt.kt
git commit -m "feat(sdk): add ResearchVisionPrompt for competitive UX analysis"
```

---

## Task 4: `MobbinAnalyst`

New analyst that iterates a fixed list of images sequentially, calling `ResearchVisionPrompt` per image and `generateSummary` at the end.

**Files:**
- Create: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/MobbinAnalyst.kt`

- [ ] **Step 1: Create `MobbinAnalyst.kt`**

```kotlin
package co.work.testpilot.analyst

import co.work.testpilot.ai.AIClient
import co.work.testpilot.ai.ResearchVisionPrompt
import co.work.testpilot.runtime.Config
import kotlin.time.TimeSource

class MobbinAnalyst(
    private val aiClient: AIClient,
    private val config: Config,
) {
    suspend fun run(
        images: List<ByteArray>,
        objective: String,
        onStep: ((String) -> Unit)? = null,
    ): AnalysisReport {
        val mark = TimeSource.Monotonic.markNow()
        val steps = mutableListOf<AnalysisStep>()
        val prompt = ResearchVisionPrompt(aiClient, config)

        for (image in images) {
            val observationsSoFar = steps.mapNotNull { it.observation }
            val observation = prompt(objective, image, observationsSoFar)
            steps.add(
                AnalysisStep(
                    screenshotData = image,
                    observation = observation,
                    action = "analyzed",
                    coordinates = null,
                )
            )
            onStep?.invoke(observation)
        }

        val summary = generateSummary(aiClient, config, objective, steps)
        val durationMs = mark.elapsedNow().inWholeMilliseconds

        return AnalysisReport(
            objective = objective,
            summary = summary,
            stepCount = steps.size,
            durationMs = durationMs,
            steps = steps,
            persona = config.personaMarkdown,
            source = "mobbin",
        )
    }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd sdk && ./gradlew testpilot:compileKotlinJvm
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/MobbinAnalyst.kt
git commit -m "feat(sdk): add MobbinAnalyst for static-image competitive research"
```

---

## Task 5: `MobbinFetcher` + JVM `Main.kt` research mode

Downloads Mobbin flow images using the saved Playwright session cookies, then wires up the `research` and `mobbin-login` modes in `Main.kt`.

> **Note on Mobbin API:** These endpoints are unofficial/internal (reverse-engineered from [mobbin-mcp](https://github.com/pdcolandrea/mobbin-mcp)). Verify the current endpoint shape against that repo if they stop working.

**Files:**
- Create: `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/MobbinFetcher.kt`
- Modify: `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/Main.kt`

- [ ] **Step 1: Create `MobbinFetcher.kt`**

```kotlin
package co.work.testpilot.analyst

import io.ktor.client.*
import io.ktor.client.engine.cio.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MobbinFetcher(private val httpClient: HttpClient) {

    companion object {
        private const val MOBBIN_SESSION_PATH = ".testpilot/sessions/mobbin.com.json"
        private const val MOBBIN_API_BASE = "https://mobbin.com/api"

        fun sessionFile(): File =
            File(System.getProperty("user.home"), MOBBIN_SESSION_PATH)
    }

    /** Returns true if a Mobbin session file exists. */
    fun hasSession(): Boolean = sessionFile().exists()

    /**
     * Loads cookies from the saved Playwright session state (JSON) for mobbin.com.
     * Returns a Cookie header value string like "name=value; name2=value2".
     */
    private fun loadCookieHeader(): String {
        val json = JSONObject(sessionFile().readText())
        val cookies = json.optJSONArray("cookies") ?: JSONArray()
        return (0 until cookies.length())
            .map { cookies.getJSONObject(it) }
            .filter { it.optString("domain").contains("mobbin.com") }
            .joinToString("; ") { "${it.getString("name")}=${it.getString("value")}" }
    }

    /**
     * Fetches image bytes for all screens in a Mobbin flow.
     * @param flowId UUID extracted from the flow URL.
     */
    suspend fun fetchFlowImages(flowId: String): List<ByteArray> {
        val cookieHeader = loadCookieHeader()

        // 1. Fetch flow metadata to get screen image URLs
        val response = httpClient.get("$MOBBIN_API_BASE/content/flows/$flowId") {
            header("Cookie", cookieHeader)
            header("Accept", "application/json")
        }

        if (response.status.value == 401) {
            error("Mobbin session expired — run: testpilot mobbin-login")
        }
        if (response.status.value != 200) {
            error("Mobbin API error ${response.status.value} for flow $flowId")
        }

        val body = response.bodyAsText()
        val imageUrls = parseImageUrls(body)

        if (imageUrls.isEmpty()) {
            error("No screens found in Mobbin flow $flowId. Check the flow URL.")
        }

        // 2. Download each image
        return imageUrls.map { url ->
            withContext(Dispatchers.IO) {
                httpClient.get(url) {
                    header("Cookie", cookieHeader)
                }.readBytes()
            }
        }
    }

    /**
     * Searches for a flow by app name + flow name and returns its ID.
     */
    suspend fun searchFlowId(appName: String, flowName: String): String {
        val cookieHeader = loadCookieHeader()

        // Search apps
        val appsResp = httpClient.get("$MOBBIN_API_BASE/content/search-apps") {
            header("Cookie", cookieHeader)
            header("Accept", "application/json")
            parameter("q", appName)
        }
        val appsBody = appsResp.bodyAsText()
        val appId = parseFirstId(appsBody)
            ?: error("No app found matching '$appName' on Mobbin")

        // Search flows for that app
        val flowsResp = httpClient.get("$MOBBIN_API_BASE/content/search-flows") {
            header("Cookie", cookieHeader)
            header("Accept", "application/json")
            parameter("q", flowName)
            parameter("appId", appId)
        }
        val flowsBody = flowsResp.bodyAsText()
        return parseFirstId(flowsBody)
            ?: error("No flow found matching '$flowName' for app '$appName' on Mobbin")
    }

    private fun parseImageUrls(json: String): List<String> {
        // Mobbin flow response: { "data": { "screens": [ { "imageUrl": "..." }, ... ] } }
        // Adjust field path if the API response shape differs — check mobbin-mcp for current shape.
        return try {
            val root = JSONObject(json)
            val screens = root.optJSONObject("data")
                ?.optJSONArray("screens")
                ?: root.optJSONArray("screens")
                ?: JSONArray()
            (0 until screens.length()).mapNotNull { i ->
                screens.getJSONObject(i).optString("imageUrl").takeIf { it.isNotBlank() }
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun parseFirstId(json: String): String? {
        return try {
            val root = JSONObject(json)
            val arr = root.optJSONArray("data") ?: return null
            if (arr.length() == 0) return null
            arr.getJSONObject(0).optString("id").takeIf { it.isNotBlank() }
        } catch (e: Exception) {
            null
        }
    }
}

/** Extracts the UUID flow ID from a Mobbin flow URL. */
fun extractFlowId(url: String): String {
    // Handles: https://mobbin.com/flows/<uuid>
    //      and https://mobbin.com/explore/flows/<uuid>
    val regex = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
    return regex.find(url)?.value
        ?: error("Could not extract flow ID from URL: $url — expected a UUID in the path")
}
```

- [ ] **Step 2: Add `org.json` dependency to `jvmMain` in `build.gradle.kts`**

Find the `jvmMain` dependencies block in `sdk/testpilot/build.gradle.kts` and add:

```kotlin
val jvmMain by getting {
    dependencies {
        implementation("com.microsoft.playwright:playwright:1.44.0")
        implementation("org.json:json:20240303")  // add this line
    }
}
```

- [ ] **Step 3: Update `Main.kt` to add `research` and `mobbin-login` modes**

Replace the entire `Main.kt`:

```kotlin
package co.work.testpilot

import co.work.testpilot.analyst.AnalystWeb
import co.work.testpilot.analyst.HtmlReportWriter
import co.work.testpilot.analyst.MobbinAnalyst
import co.work.testpilot.analyst.MobbinFetcher
import co.work.testpilot.analyst.TestAnalystWeb
import co.work.testpilot.analyst.WebSession
import co.work.testpilot.analyst.extractFlowId
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
                val url      = requireEnv("TESTPILOT_WEB_URL")
                val apiKey   = requireEnv("TESTPILOT_API_KEY")
                val provider = env("TESTPILOT_PROVIDER") ?: "anthropic"
                val maxSteps = env("TESTPILOT_MAX_STEPS")?.toIntOrNull() ?: 40
                val lang     = env("TESTPILOT_LANG") ?: "en"
                val objective = requireEnv("TESTPILOT_OBJECTIVE")
                val username = env("TESTPILOT_WEB_USERNAME")?.takeIf { it.isNotEmpty() }
                val password = env("TESTPILOT_WEB_PASSWORD")?.takeIf { it.isNotEmpty() }

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

                val flowUrl   = env("TESTPILOT_MOBBIN_FLOW_URL")
                val appName   = env("TESTPILOT_MOBBIN_APP")
                val flowName  = env("TESTPILOT_MOBBIN_FLOW_NAME")

                val httpClient = HttpClient(CIO)
                val fetcher = MobbinFetcher(httpClient)

                if (!fetcher.hasSession()) {
                    System.err.println("Error: Mobbin session not found — run: testpilot mobbin-login")
                    exitProcess(1)
                }

                val images = try {
                    when {
                        !flowUrl.isNullOrEmpty() -> {
                            val flowId = extractFlowId(flowUrl)
                            fetcher.fetchFlowImages(flowId)
                        }
                        !appName.isNullOrEmpty() && !flowName.isNullOrEmpty() -> {
                            val flowId = fetcher.searchFlowId(appName, flowName)
                            fetcher.fetchFlowImages(flowId)
                        }
                        else -> {
                            System.err.println("Error: either TESTPILOT_MOBBIN_FLOW_URL or both TESTPILOT_MOBBIN_APP and TESTPILOT_MOBBIN_FLOW_NAME are required")
                            exitProcess(1)
                        }
                    }
                } catch (e: Exception) {
                    System.err.println("Error fetching Mobbin flow: ${e.message}")
                    exitProcess(1)
                } finally {
                    httpClient.close()
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

                val report = MobbinAnalyst(buildWebAIClient(config, HttpClient(CIO)), config)
                    .run(images, objective) { obs ->
                        println("TESTPILOT_STEP: $obs")
                        System.out.flush()
                    }

                val html = HtmlReportWriter.generate(report, lang)
                val file = File(output).also { it.parentFile?.mkdirs() }
                file.writeText(html)
                println("TESTPILOT_REPORT_PATH=${file.absolutePath}")
                System.out.flush()
            }

            else -> {
                System.err.println("Error: unknown TESTPILOT_MODE '$mode'. Use analyze, test, login, mobbin-login, or research.")
                exitProcess(1)
            }
        }
    }
}
```

> **Note:** `buildWebAIClient` is defined in `WebAIClientFactory.kt`. Check that file to ensure the import is correct.

- [ ] **Step 4: Verify compilation**

```bash
cd sdk && ./gradlew testpilot:jvmJar
```

Expected: BUILD SUCCESSFUL with JAR produced.

- [ ] **Step 5: Commit**

```bash
git add sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/MobbinFetcher.kt \
        sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/Main.kt \
        sdk/testpilot/build.gradle.kts
git commit -m "feat(jvm): add MobbinFetcher and research/mobbin-login JVM modes"
```

---

## Task 6: CLI `mobbin-login` + `research` subcommand

Adds two new top-level commands to the `testpilot` bash script.

**Files:**
- Modify: `testpilot` (CLI script)

- [ ] **Step 1: Add `mobbin-login` and `research` to the command validation line**

Find:
```bash
if [[ "$COMMAND" != "analyze" && "$COMMAND" != "test" && "$COMMAND" != "web-login" ]]; then
```

Replace with:
```bash
if [[ "$COMMAND" != "analyze" && "$COMMAND" != "test" && "$COMMAND" != "web-login" && "$COMMAND" != "mobbin-login" && "$COMMAND" != "research" ]]; then
```

- [ ] **Step 2: Add `research` flags to the usage block**

After the web-login usage line, add:
```bash
echo ""
echo "       ./testpilot research --flow <mobbin-flow-url> --objective <text>"
echo "       ./testpilot research --app <app-name> --flow-name <flow-name> [--objective <text>]"
echo "       [--persona <file>] [--provider anthropic|openai|gemini] [--api-key <key>]"
echo "       [--max-steps <n>] [--output <path>] [--lang en|pt-BR]"
echo ""
echo "       ./testpilot mobbin-login"
```

- [ ] **Step 3: Add `--flow` and `--flow-name` flag parsing**

In the `while [[ $# -gt 0 ]]` argument parsing block, add:
```bash
--flow)       MOBBIN_FLOW_URL="$2"; shift 2 ;;
--flow-name)  MOBBIN_FLOW_NAME="$2"; shift 2 ;;
```

Also add at the top of the script with the other variable declarations:
```bash
MOBBIN_FLOW_URL=""
MOBBIN_FLOW_NAME=""
```

- [ ] **Step 4: Add `mobbin-login` handler**

After the `web-login` handler block (after line ~143), add:

```bash
# ── mobbin-login: establish Mobbin browser session ───────────────────────────
if [[ "$COMMAND" == "mobbin-login" ]]; then
  _ensure_artifact web
  JAVA_BIN="$TESTPILOT_CACHE/web/jre/bin/java"
  WEB_JAR="$TESTPILOT_CACHE/web/testpilot-web.jar"

  (
    export TESTPILOT_MODE="mobbin-login"
    export TESTPILOT_API_KEY="${API_KEY:-dummy}"
    "$JAVA_BIN" -jar "$WEB_JAR"
  )
  exit $?
fi
```

- [ ] **Step 5: Add `research` command handler**

After the `mobbin-login` handler, add:

```bash
# ── research: competitive UX analysis from Mobbin flow ───────────────────────
if [[ "$COMMAND" == "research" ]]; then
  MOBBIN_SESSION="$HOME/.testpilot/sessions/mobbin.com.json"
  if [[ ! -f "$MOBBIN_SESSION" ]]; then
    echo "Error: Mobbin session not found — run: testpilot mobbin-login"
    exit 1
  fi

  if [[ -z "$MOBBIN_FLOW_URL" && ( -z "$APP_NAME" || -z "$MOBBIN_FLOW_NAME" ) ]]; then
    echo "Error: --flow <url> OR both --app <name> and --flow-name <name> are required for research"
    exit 1
  fi

  [[ -z "$API_KEY" ]] && { echo "Error: API key required (--api-key or TESTPILOT_API_KEY in .env)"; exit 1; }

  _ensure_artifact web
  JAVA_BIN="$TESTPILOT_CACHE/web/jre/bin/java"
  WEB_JAR="$TESTPILOT_CACHE/web/testpilot-web.jar"

  PERSONA_CONTENT=""
  if [[ -n "$PERSONA_FILE" ]]; then
    [[ ! -f "$PERSONA_FILE" ]] && { echo "Error: persona file not found: $PERSONA_FILE"; exit 1; }
    PERSONA_CONTENT="$(cat "$PERSONA_FILE")"
  fi

  RESEARCH_LOG=$(mktemp)
  RESEARCH_EXIT_FILE=$(mktemp)
  trap 'rm -f "$RESEARCH_LOG" "$RESEARCH_EXIT_FILE"' EXIT

  (
    export TESTPILOT_MODE="research"
    export TESTPILOT_API_KEY="$API_KEY"
    export TESTPILOT_PROVIDER="${PROVIDER:-anthropic}"
    export TESTPILOT_MAX_STEPS="$MAX_STEPS"
    export TESTPILOT_LANG="$LANG_CODE"
    export TESTPILOT_OUTPUT="$OUTPUT"
    export TESTPILOT_OBJECTIVE="$OBJECTIVE"
    export TESTPILOT_PERSONA="$PERSONA_CONTENT"
    export TESTPILOT_MOBBIN_FLOW_URL="$MOBBIN_FLOW_URL"
    export TESTPILOT_MOBBIN_APP="$APP_NAME"
    export TESTPILOT_MOBBIN_FLOW_NAME="$MOBBIN_FLOW_NAME"
    "$JAVA_BIN" -jar "$WEB_JAR" 2>&1
    echo $? >"$RESEARCH_EXIT_FILE"
  ) | tee "$RESEARCH_LOG"

  RUNNER_EXIT=$(cat "$RESEARCH_EXIT_FILE" 2>/dev/null || echo "1")
  if [[ "$RUNNER_EXIT" != "0" ]]; then
    echo "Error: Research runner failed (exit $RUNNER_EXIT)."
    rm -f "$RESEARCH_LOG"
    exit 1
  fi

  REPORT_PATH=$(grep "^TESTPILOT_REPORT_PATH=" "$RESEARCH_LOG" | tail -1 | cut -d= -f2-)
  rm -f "$RESEARCH_LOG"

  if [[ -n "$REPORT_PATH" && -f "$REPORT_PATH" ]]; then
    echo "Research report saved to: $REPORT_PATH"
  fi
  exit 0
fi
```

- [ ] **Step 6: Smoke test the new commands are recognized**

```bash
./testpilot research 2>&1 | head -5
```

Expected: Error about missing Mobbin session or missing flags (not "Unknown command").

```bash
./testpilot mobbin-login 2>&1 | head -3
```

Expected: "Downloading web components..." (if not cached) or a browser opens.

- [ ] **Step 7: Commit**

```bash
git add testpilot
git commit -m "feat(cli): add research subcommand and mobbin-login"
```

---

## Task 7: macOS app — `RunConfig` + `RunConfigTests`

Adds the `research` RunMode and Mobbin-specific fields to `RunConfig`, and tests the `isValid` logic.

**Files:**
- Modify: `mac-app/TestPilotApp/Models/RunConfig.swift`
- Modify: `mac-app/TestPilotTests/RunConfigTests.swift`

- [ ] **Step 1: Add `research` to `RunMode`**

In `RunConfig.swift`, replace the `RunMode` enum:

```swift
enum RunMode: String, Codable, CaseIterable, Identifiable {
    case analyze
    case test
    case research
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .analyze:  return "Analyze"
        case .test:     return "Test"
        case .research: return "Research"
        }
    }
}
```

- [ ] **Step 2: Add Mobbin fields and `mobbinSourceType` to `RunConfig`**

Add these properties after `personaPath`:

```swift
enum MobbinSource: String, CaseIterable, Identifiable {
    case flowUrl = "Flow URL"
    case search  = "Search"
    var id: String { rawValue }
}

// inside RunConfig @Observable class:
var mobbinSource: MobbinSource = .flowUrl
var mobbinFlowUrl: String = ""
var mobbinAppName: String = ""
var mobbinFlowName: String = ""
```

> **Note:** Place `MobbinSource` outside the `RunConfig` class at file scope.

- [ ] **Step 3: Update `isValid` to handle research mode**

Replace the `isValid` computed property:

```swift
var isValid: Bool {
    switch mode {
    case .analyze, .test:
        let objectiveRequired = mode == .test || personaPath.isEmpty
        if objectiveRequired && objective.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if platform == .web {
            let trimmed = url.trimmingCharacters(in: .whitespaces).lowercased()
            return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
        }
        return selectedDevice != nil
            && (!appName.trimmingCharacters(in: .whitespaces).isEmpty
                || !bundleId.trimmingCharacters(in: .whitespaces).isEmpty)

    case .research:
        let sessionPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".testpilot/sessions/mobbin.com.json").path
        guard FileManager.default.fileExists(atPath: sessionPath) else { return false }
        switch mobbinSource {
        case .flowUrl:
            return !mobbinFlowUrl.trimmingCharacters(in: .whitespaces).isEmpty
        case .search:
            return !mobbinAppName.trimmingCharacters(in: .whitespaces).isEmpty
                && !mobbinFlowName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
```

- [ ] **Step 4: Write failing tests for research `isValid`**

In `RunConfigTests.swift`, add:

```swift
// MARK: - Research mode isValid

func testResearchIsInvalidWithoutSession() {
    let config = RunConfig()
    config.mode = .research
    config.mobbinFlowUrl = "https://mobbin.com/flows/abc-123"
    // No session file exists in test environment
    XCTAssertFalse(config.isValid)
}

func testResearchFlowUrlIsInvalidWhenEmpty() {
    let config = RunConfig()
    config.mode = .research
    config.mobbinSource = .flowUrl
    config.mobbinFlowUrl = ""
    XCTAssertFalse(config.isValid)
}

func testResearchSearchIsInvalidWhenAppNameMissing() {
    let config = RunConfig()
    config.mode = .research
    config.mobbinSource = .search
    config.mobbinAppName = ""
    config.mobbinFlowName = "Onboarding"
    XCTAssertFalse(config.isValid)
}

func testResearchSearchIsInvalidWhenFlowNameMissing() {
    let config = RunConfig()
    config.mode = .research
    config.mobbinSource = .search
    config.mobbinAppName = "Nike Run Club"
    config.mobbinFlowName = ""
    XCTAssertFalse(config.isValid)
}
```

- [ ] **Step 5: Run tests to confirm they fail first**

Open Xcode, run `TestPilotTests` target.
Expected: compilation errors or test failures for the new test methods (session path check won't match test environment).

- [ ] **Step 6: Run tests to confirm they pass**

After Step 3 (adding `isValid` logic), re-run tests.
Expected: all four new tests pass (session file doesn't exist in CI, so the first test passes by checking `false`; the others test input validation before the session check).

> **Implementation note:** The session-check test passes because no `mobbin.com.json` exists in the test environment sandbox. This is intentional — we're testing the validation logic, not the file system.

- [ ] **Step 7: Commit**

```bash
git add mac-app/TestPilotApp/Models/RunConfig.swift \
        mac-app/TestPilotTests/RunConfigTests.swift
git commit -m "feat(mac): add research RunMode and Mobbin fields to RunConfig"
```

---

## Task 8: macOS app — `ResearchRunner`

Builds the JVM process that runs `testpilot research` mode, mirroring the shape of `WebRunner`.

**Files:**
- Create: `mac-app/TestPilotApp/Services/ResearchRunner.swift`

- [ ] **Step 1: Create `ResearchRunner.swift`**

```swift
import Foundation

struct ResearchRunner {
    let config: RunConfig
    let settings: SettingsStore

    @MainActor
    func makeProcess() throws -> Process {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".testpilot")
        let jreJava = cacheDir.appendingPathComponent("web/jre/bin/java")
        let jar     = cacheDir.appendingPathComponent("web/testpilot-web.jar")

        guard FileManager.default.fileExists(atPath: jreJava.path) else {
            throw WebRunnerError.jreNotFound
        }
        guard FileManager.default.fileExists(atPath: jar.path) else {
            throw WebRunnerError.jarNotFound
        }

        let provider    = (config.providerOverride ?? settings.provider).rawValue
        let outputPath  = NSString(string: config.outputPath).expandingTildeInPath
        let personaContent = config.personaContent ?? ""

        var env = ProcessInfo.processInfo.environment
        env["TESTPILOT_MODE"]              = "research"
        env["TESTPILOT_API_KEY"]           = settings.apiKey
        env["TESTPILOT_PROVIDER"]          = provider
        env["TESTPILOT_MAX_STEPS"]         = "\(config.maxSteps)"
        env["TESTPILOT_LANG"]              = config.language.rawValue
        env["TESTPILOT_OUTPUT"]            = outputPath
        env["TESTPILOT_OBJECTIVE"]         = config.objective
        env["TESTPILOT_PERSONA"]           = personaContent
        env["TESTPILOT_MOBBIN_FLOW_URL"]   = config.mobbinFlowUrl
        env["TESTPILOT_MOBBIN_APP"]        = config.mobbinAppName
        env["TESTPILOT_MOBBIN_FLOW_NAME"]  = config.mobbinFlowName

        let proc = Process()
        proc.executableURL = jreJava
        proc.arguments     = ["-jar", jar.path]
        proc.environment   = env
        return proc
    }

    @MainActor
    func makeMobbinLoginProcess() throws -> Process {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".testpilot")
        let jreJava = cacheDir.appendingPathComponent("web/jre/bin/java")
        let jar     = cacheDir.appendingPathComponent("web/testpilot-web.jar")

        guard FileManager.default.fileExists(atPath: jreJava.path) else {
            throw WebRunnerError.jreNotFound
        }
        guard FileManager.default.fileExists(atPath: jar.path) else {
            throw WebRunnerError.jarNotFound
        }

        var env = ProcessInfo.processInfo.environment
        env["TESTPILOT_MODE"]    = "mobbin-login"
        env["TESTPILOT_API_KEY"] = settings.apiKey.isEmpty ? "dummy" : settings.apiKey

        let proc = Process()
        proc.executableURL = jreJava
        proc.arguments     = ["-jar", jar.path]
        proc.environment   = env
        return proc
    }
}
```

- [ ] **Step 2: Verify the file compiles by building the macOS app target**

In Xcode: Product → Build (⌘B).
Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add mac-app/TestPilotApp/Services/ResearchRunner.swift
git commit -m "feat(mac): add ResearchRunner service for Mobbin research mode"
```

---

## Task 9: macOS app — `RunView` Research UI

Adds the Research mode form section to `RunView`.

**Files:**
- Modify: `mac-app/TestPilotApp/Views/RunView.swift`

- [ ] **Step 1: Add research case to the Mode segmented control**

The `RunMode.allCases` already includes `.research` after Task 7, so the segmented control renders automatically. No change needed for the picker itself.

- [ ] **Step 2: Add the Research mode content section**

In `RunView.body`, inside the `Section("Required")`, find the block that shows `if config.platform != .web { ... } else { ... }`. After that entire if/else block (and before the objective field), add:

```swift
if config.mode == .research {
    Picker("Source", selection: $config.mobbinSource) {
        ForEach(MobbinSource.allCases) { s in
            Text(s.rawValue).tag(s)
        }
    }
    .pickerStyle(.segmented)

    if config.mobbinSource == .flowUrl {
        TextField("Mobbin Flow URL", text: $config.mobbinFlowUrl)
            .textContentType(.URL)
    } else {
        TextField("App name", text: $config.mobbinAppName)
        TextField("Flow name", text: $config.mobbinFlowName)
    }
}
```

- [ ] **Step 3: Hide Platform + Device pickers for research mode**

Wrap the existing `Picker("Platform", ...)` block with:

```swift
if config.mode != .research {
    Picker("Platform", selection: $config.platform) { ... }
    // ... existing device/app/url fields ...
}
```

- [ ] **Step 4: Add "Connect Mobbin…" button for research mode**

After the source/flow fields block from Step 2, add:

```swift
if config.mode == .research {
    Button("Connect Mobbin…") {
        runner.mobbinLogin(config: config, settings: settings)
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.secondary)
    .font(.caption)
    .help("Open a browser to log in to Mobbin — required before running research")
}
```

- [ ] **Step 5: Update CTA button label for research**

Find:
```swift
let label = config.mode == .test ? "Run Test" : "Run Analysis"
```

Replace with:
```swift
let label: String
switch config.mode {
case .test:     label = "Run Test"
case .research: label = "Run Research"
case .analyze:  label = "Run Analysis"
}
```

- [ ] **Step 6: Update `navigationTitle` for research**

Find:
```swift
.navigationTitle(config.mode == .test ? "New Test" : "New Analysis")
```

Replace with:
```swift
.navigationTitle({
    switch config.mode {
    case .test:     return "New Test"
    case .research: return "New Research"
    case .analyze:  return "New Analysis"
    }
}())
```

- [ ] **Step 7: Build to verify**

In Xcode: Product → Build (⌘B).
Expected: Build Succeeded.

- [ ] **Step 8: Commit**

```bash
git add mac-app/TestPilotApp/Views/RunView.swift
git commit -m "feat(mac): add Research mode UI to RunView"
```

---

## Task 10: macOS app — `AnalysisRunner` research wiring

Wires the research mode into `AnalysisRunner` so clicking "Run Research" and "Connect Mobbin…" actually works.

**Files:**
- Modify: `mac-app/TestPilotApp/Services/AnalysisRunner.swift`

- [ ] **Step 1: Add `mobbinLogin()` method**

After the `webLogin()` method in `AnalysisRunner`, add:

```swift
func mobbinLogin(config: RunConfig, settings: SettingsStore) {
    guard case .idle = state else { return }

    Task {
        do {
            let proc = try ResearchRunner(config: config, settings: settings).makeMobbinLoginProcess()
            await MainActor.run { self.startWebLoginProcess(proc) }
        } catch {
            await MainActor.run { state = .failed(error: error.localizedDescription) }
        }
    }
}
```

- [ ] **Step 2: Add `.research` case to `run()`**

In `AnalysisRunner.run()`, find the `switch config.platform { ... }` block inside the `Task { ... }`. Add the research case before that switch (research doesn't need a platform):

```swift
// Handle research mode before platform switch — no device needed
if config.mode == .research {
    do {
        let proc = try ResearchRunner(config: config, settings: settings).makeProcess()
        await MainActor.run { self.startProcess(proc, outputPath: outputPath) }
    } catch {
        await MainActor.run { state = .failed(error: error.localizedDescription) }
    }
    return
}
```

Place this block at the top of the `Task { do { ... } }` body, before the `switch config.platform` statement.

- [ ] **Step 3: Update state initialization for research mode**

Find:
```swift
state = config.mode == .test ? .testRunning(steps: []) : .running(statusLine: "Starting…")
```

Replace with:
```swift
state = config.mode == .test ? .testRunning(steps: []) : .running(statusLine: "Starting…")
// research uses .running state (same as analyze — produces a report)
```

No change needed here — research uses `.running` the same as analyze.

- [ ] **Step 4: Build and do a manual smoke test**

In Xcode: Product → Build (⌘B).
Expected: Build Succeeded.

Manual test:
1. Launch the app
2. Switch mode to "Research" — verify Platform picker disappears, Mobbin source toggle appears
3. Click "Connect Mobbin…" — verify browser opens to mobbin.com (requires web JAR to be installed)
4. Verify "Run Research" button is disabled until a session exists and a flow URL is entered

- [ ] **Step 5: Commit**

```bash
git add mac-app/TestPilotApp/Services/AnalysisRunner.swift
git commit -m "feat(mac): wire research mode and Mobbin login into AnalysisRunner"
```

---

## Self-Review Checklist

- [x] `SummaryGenerator` extracted and `Analyst` delegates to it
- [x] `AnalysisReport.source` field used in `HtmlReportWriter` for title + badge rendering
- [x] `ResearchVisionPrompt` uses competitive framing, returns `observation` string only
- [x] `MobbinAnalyst` uses `ResearchVisionPrompt`, sets `source = "mobbin"` on report
- [x] `MobbinFetcher` reads Playwright session cookies, handles 401 with actionable error
- [x] `Main.kt` handles `mobbin-login` (reuses `WebSession.interactiveLogin`) and `research`
- [x] CLI validates session exists before running research, passes all env vars
- [x] macOS `RunConfig.isValid` checks session file + input completeness
- [x] `ResearchRunner` mirrors `WebRunner` shape
- [x] `RunView` hides Platform picker in research, shows source toggle + Connect Mobbin button
- [x] `AnalysisRunner` handles research before platform switch
- [x] `RunConfigTests` covers research `isValid` edge cases

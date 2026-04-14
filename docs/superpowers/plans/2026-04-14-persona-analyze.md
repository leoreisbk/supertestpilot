# Persona Support for Exploratory Analysis — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to supply a free-form persona `.md` file that shapes how the AI explores the app in analyze mode — navigation priorities, observations, and the final report.

**Architecture:** `personaMarkdown: String?` flows from user input → `Config` → `VisionPrompt` (system prompt injection) → `AnalysisReport` → `HtmlReportWriter` (persona card, severity badge coloring, structured markdown summary). CLI passes persona via base64-encoded `-testenv`; Mac app reads the file at run time.

**Tech Stack:** Kotlin Multiplatform (commonMain), SwiftUI (Mac app), Bash (CLI)

---

## File Structure

| Action | File |
|--------|------|
| Modify | `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/AnalysisReport.kt` |
| Modify | `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/runtime/Config.kt` |
| Modify | `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/ai/VisionPrompt.kt` |
| Modify | `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/Analyst.kt` |
| Modify | `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/HtmlReportWriter.kt` |
| Modify | `testpilot` (CLI bash script, repo root) |
| Modify | `mac-app/TestPilotApp/Models/RunConfig.swift` |
| Modify | `mac-app/TestPilotApp/Views/RunView.swift` |
| Modify | `mac-app/TestPilotApp/Services/IOSRunner.swift` |

---

### Task 1: SDK data model — Config + AnalysisReport

**Files:**
- Modify: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/AnalysisReport.kt`
- Modify: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/runtime/Config.kt`

- [ ] **Step 1: Add `persona` field to `AnalysisReport`**

  Replace the entire file with:

  ```kotlin
  package co.work.testpilot.analyst

  data class AnalysisReport(
      val objective: String,
      val summary: String,
      val stepCount: Int,
      val durationMs: Long,
      val steps: List<AnalysisStep>,
      val persona: String? = null,
  )
  ```

- [ ] **Step 2: Add `personaMarkdown` to `Config` data class**

  In `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/runtime/Config.kt`, add the field to the `Config` data class (after the `language` field):

  ```kotlin
  data class Config(
      val provider: AIProvider,
      val apiKey: String,
      val modelId: String?,
      var apiHost: String?,
      var apiOrg: String?,
      var apiHeaders: Map<String, String>,
      val maxTokens: Int,
      val temperature: Double,
      val maxSteps: Int,
      val language: String = "en",
      val personaMarkdown: String? = null,
  )
  ```

- [ ] **Step 3: Add `persona()` builder method to `ConfigBuilder`**

  In `ConfigBuilder`, add the `personaMarkdown` var and builder method. Place after the `language` var at line ~49:

  ```kotlin
  var personaMarkdown: String? = null

  @ObjCName("persona")
  fun persona(markdown: String?): ConfigBuilder {
      this.personaMarkdown = markdown
      return this
  }
  ```

  And update `build()` to include it (after `language = language,`):

  ```kotlin
  fun build(): Config = Config(
      provider = provider,
      apiKey = apiKey ?: throw ConfigurationException.ApiKeyRequired(),
      modelId = modelId,
      apiHost = apiHost,
      apiOrg = apiOrg,
      apiHeaders = apiHeaders,
      maxTokens = maxTokens,
      temperature = temperature,
      maxSteps = maxSteps,
      language = language,
      personaMarkdown = personaMarkdown,
  )
  ```

- [ ] **Step 4: Verify Kotlin compiles**

  ```bash
  cd sdk && ./gradlew testpilot:compileKotlinMetadata
  ```

  Expected: `BUILD SUCCESSFUL`

- [ ] **Step 5: Commit**

  ```bash
  git add sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/AnalysisReport.kt \
          sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/runtime/Config.kt
  git commit -m "feat(sdk): add personaMarkdown to Config and persona field to AnalysisReport"
  ```

---

### Task 2: VisionPrompt — persona injection in system prompt

**Files:**
- Modify: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/ai/VisionPrompt.kt`

- [ ] **Step 1: Add persona section to system prompt**

  In `VisionPrompt.kt`, after the `languageInstruction` variable (line ~23), add:

  ```kotlin
  val personaSection = config.personaMarkdown
      ?.takeIf { it.isNotBlank() }
      ?.let { persona ->
          """

          ## Persona
          You are evaluating this app from the perspective of the following user. Let their goals, behaviors, and pain points shape which flows you prioritize, what you notice, and how you assess the UX.

          <persona>
          $persona
          </persona>
          """.trimIndent()
      } ?: ""
  ```

- [ ] **Step 2: Append persona section to the system prompt string**

  The current system prompt ends with `$languageInstruction`. Append `$personaSection` after it:

  ```kotlin
  val systemPrompt = """
      You are a senior UX researcher conducting a structured usability evaluation of a live mobile app. Your findings will be used by product managers and designers to make product decisions — they must be specific, evidence-based, and actionable.

      ## Your job
      Explore the app with a clear focus on the stated objective. Gather evidence that directly informs whether the app succeeds or fails at that objective. Every observation must be something a PM or designer can act on.

      ## Observation quality standards
      - **Specific**: Name the exact element, screen, or flow (e.g. "Checkout → Payment screen: 'Confirm' button is below the fold on smaller devices")
      - **Evidence-based**: Describe what you actually saw (e.g. "Error message reads 'Something went wrong' with no recovery path")
      - **Actionable**: State the problem clearly enough that a designer knows what to fix
      - **No generics**: Never write "navigation could be improved" — write "Back button is missing on the Order Details screen, requiring users to swipe to go back"
      - **Severity**: Prefix critical blockers with [CRITICAL], friction points with [ISSUE], and positive UX patterns worth noting with [POSITIVE]

      ## Navigation rules
      - Stay focused on the objective — explore flows directly related to what you're evaluating
      - Use "type" — NOT "tap" — for text fields, search bars, or any input that accepts keyboard text. Always include a realistic value
      - Never tap the same element twice without a visible change
      - If stuck, scroll or navigate back to find a new path

      Respond ONLY with a single valid JSON object. No markdown, no explanation, no extra text.
      $languageInstruction$personaSection
  """.trimIndent()
  ```

- [ ] **Step 3: Verify Kotlin compiles**

  ```bash
  cd sdk && ./gradlew testpilot:compileKotlinMetadata
  ```

  Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: Commit**

  ```bash
  git add sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/ai/VisionPrompt.kt
  git commit -m "feat(sdk): inject persona into VisionPrompt system prompt"
  ```

---

### Task 3: Analyst — propagate persona to report and summary

**Files:**
- Modify: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/Analyst.kt`

- [ ] **Step 1: Pass `persona` to `AnalysisReport` in `run()`**

  In `Analyst.kt`, the `return AnalysisReport(...)` block (line ~70) currently has 5 fields. Add `persona`:

  ```kotlin
  return AnalysisReport(
      objective = objective,
      summary = summary,
      stepCount = steps.size,
      durationMs = durationMs,
      steps = steps,
      persona = config.personaMarkdown,
  )
  ```

- [ ] **Step 2: Frame `generateSummary` with persona when present**

  In `generateSummary`, after the `languageInstruction` variable, add:

  ```kotlin
  val personaContext = if (config.personaMarkdown.isNullOrBlank()) "" else """

  This evaluation was conducted from the perspective of:
  <persona>
  ${config.personaMarkdown}
  </persona>

  Frame your findings through the lens of this persona's goals and pain points.
  """.trimIndent()
  ```

  Then append `$personaContext` to the prompt string, after `$languageInstruction`:

  ```kotlin
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
  ```

- [ ] **Step 3: Verify Kotlin compiles**

  ```bash
  cd sdk && ./gradlew testpilot:compileKotlinMetadata
  ```

  Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: Commit**

  ```bash
  git add sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/Analyst.kt
  git commit -m "feat(sdk): propagate persona to AnalysisReport and generateSummary"
  ```

---

### Task 4: HtmlReportWriter — persona card, severity badges, markdown rendering

**Files:**
- Modify: `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/HtmlReportWriter.kt`

This is the largest change. Replace the file entirely with the version below. Key additions:
- `renderObservation()` — parses `[CRITICAL]`/`[ISSUE]`/`[POSITIVE]` prefix into colored badge
- `renderSummaryMarkdown()` + `renderBold()` — converts `**bold**` and `- bullets` to HTML
- Persona card in the header (visible only when `report.persona != null`)
- New CSS for badges, persona card, summary lists
- `Labels` gains `evaluatedAs` field for i18n

- [ ] **Step 1: Replace `HtmlReportWriter.kt` with the updated version**

  ```kotlin
  package co.work.testpilot.analyst

  import kotlin.io.encoding.Base64
  import kotlin.io.encoding.ExperimentalEncodingApi

  object HtmlReportWriter {

      private data class Labels(
          val htmlLang: String,
          val title: String,
          val summary: String,
          val stepByStep: String,
          val step: String,
          val steps: String,
          val evaluatedAs: String,
      )

      private fun labelsFor(language: String): Labels = when (language) {
          "pt-BR", "pt" -> Labels(
              htmlLang    = "pt-BR",
              title       = "Relatório de Análise TestPilot",
              summary     = "Resumo",
              stepByStep  = "Passo a passo",
              step        = "Passo",
              steps       = "passos",
              evaluatedAs = "Avaliado como",
          )
          else -> Labels(
              htmlLang    = "en",
              title       = "TestPilot Analysis Report",
              summary     = "Summary",
              stepByStep  = "Step-by-step",
              step        = "Step",
              steps       = "steps",
              evaluatedAs = "Evaluated as",
          )
      }

      @OptIn(ExperimentalEncodingApi::class)
      fun generate(report: AnalysisReport, language: String = "en"): String {
          val lbl = labelsFor(language)
          val stepsHtml = report.steps.mapIndexed { index, step ->
              val base64 = Base64.encode(step.screenshotData)
              val obsContent = step.observation
                  ?.takeIf { it.isNotBlank() }
                  ?.let { "<p>${renderObservation(it)}</p>" }
                  ?: "<p class=\"step-obs-empty\">—</p>"
              val coordHtml = step.coordinates
                  ?.let { (x, y) -> "<span class=\"coord\">(${fmtCoord(x)}, ${fmtCoord(y)})</span>" }
                  ?: ""
              """
              <div class="step">
                <div class="step-header">
                  <span class="step-num">${lbl.step} ${index + 1}</span>
                  <span class="action">${step.action.htmlEscape()}</span>
                  $coordHtml
                </div>
                <div class="step-body">
                  <div class="step-img-col">
                    <img src="data:${step.screenshotData.imageMimeType()};base64,$base64" alt="${lbl.step} ${index + 1}" loading="lazy" />
                  </div>
                  <div class="step-obs-col">
                    $obsContent
                  </div>
                </div>
              </div>
              """.trimIndent()
          }.joinToString("\n")

          val durationText = fmtDuration(report.durationMs)

          val personaCardHtml = report.persona
              ?.takeIf { it.isNotBlank() }
              ?.let { persona ->
                  val firstLine = persona.lines()
                      .firstOrNull { it.isNotBlank() }
                      ?.trimStart('#', ' ')
                      ?.htmlEscape()
                      ?: ""
                  val fullPersona = persona.htmlEscape()
                  """
                  <div class="persona-card">
                    <span class="persona-icon">👤</span>
                    <div class="persona-content">
                      <div class="persona-label">${lbl.evaluatedAs}</div>
                      <div class="persona-text">$firstLine</div>
                      <details>
                        <summary class="persona-show-more">Show full persona</summary>
                        <pre class="persona-full">$fullPersona</pre>
                      </details>
                    </div>
                  </div>
                  """.trimIndent()
              } ?: ""

          return """
          <!DOCTYPE html>
          <html lang="${lbl.htmlLang}">
          <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>${lbl.title}</title>
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                   background: #f5f5f7; color: #1d1d1f; line-height: 1.5; }
            .header { background: #fff; padding: 32px 40px; border-bottom: 1px solid #e5e5ea; }
            .header h1 { font-size: 22px; font-weight: 600; margin-bottom: 8px; }
            .header .objective { color: #6e6e73; font-size: 15px; }
            .meta { margin-top: 12px; font-size: 13px; color: #8e8e93; }
            .persona-card { display: flex; gap: 10px; align-items: flex-start; margin-top: 14px;
                            background: #f2f2f7; border-radius: 8px; padding: 10px 14px; }
            .persona-icon { font-size: 20px; line-height: 1.3; }
            .persona-label { font-size: 11px; color: #8e8e93; text-transform: uppercase;
                             letter-spacing: .04em; }
            .persona-text  { font-size: 13px; font-weight: 500; margin-top: 2px; color: #1d1d1f; }
            .persona-show-more { font-size: 12px; color: #007aff; cursor: pointer; margin-top: 4px; }
            .persona-full  { font-size: 12px; color: #6e6e73; margin-top: 6px;
                             white-space: pre-wrap; line-height: 1.5; font-family: inherit; }
            .summary-box { margin: 24px 40px; background: #fff; border-radius: 12px;
                           padding: 20px 24px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
            .summary-box h2 { font-size: 15px; font-weight: 600; margin-bottom: 8px; }
            .summary-content { font-size: 14px; color: #3a3a3c; }
            .summary-content p { margin-bottom: 6px; }
            .summary-content ul { padding-left: 18px; margin: 4px 0 8px; }
            .summary-content li { margin-bottom: 3px; }
            .summary-content strong { font-weight: 600; }
            .steps { padding: 0 40px 40px; }
            .steps h2 { font-size: 15px; font-weight: 600; margin: 24px 0 12px; }
            .step { background: #fff; border-radius: 12px; margin-bottom: 16px;
                    box-shadow: 0 1px 3px rgba(0,0,0,.08); }
            .step-header { display: flex; align-items: center; gap: 10px;
                           padding: 12px 16px; background: #f2f2f7;
                           border-radius: 12px 12px 0 0; }
            .step-num { font-size: 12px; color: #8e8e93; }
            .action { font-size: 13px; font-weight: 600; background: #007aff;
                      color: #fff; padding: 2px 8px; border-radius: 4px; }
            .coord { font-size: 12px; color: #8e8e93; font-family: monospace; }
            .step-body { display: flex; flex-direction: row; align-items: flex-start; }
            .step-img-col { flex: 0 0 40%; padding: 12px; }
            .step-img-col img { display: block; width: 100%; height: auto; border-radius: 8px; }
            .step-obs-col { flex: 1; padding: 16px 16px 16px 8px;
                            font-size: 14px; line-height: 1.6; color: #3a3a3c; }
            .step-obs-empty { color: #aeaeb2; font-style: italic; }
            .badge { display: inline-block; font-size: 10px; font-weight: 700; letter-spacing: .06em;
                     padding: 1px 6px; border-radius: 3px; margin-right: 6px; vertical-align: middle; }
            .badge-critical { background: #ff3b30; color: #fff; }
            .badge-issue    { background: #ff9500; color: #fff; }
            .badge-positive { background: #34c759; color: #fff; }
            @media (max-width: 600px) {
              .step-body { flex-direction: column; }
              .step-img-col { flex: none; width: 100%; }
            }
            @media (prefers-color-scheme: dark) {
              body { background: #1c1c1e; color: #f5f5f7; }
              .header { background: #2c2c2e; border-bottom-color: #3a3a3c; }
              .header .objective { color: #aeaeb2; }
              .meta { color: #636366; }
              .persona-card  { background: #3a3a3c; }
              .persona-text  { color: #f5f5f7; }
              .persona-label { color: #636366; }
              .persona-full  { color: #aeaeb2; }
              .summary-box { background: #2c2c2e; box-shadow: 0 1px 3px rgba(0,0,0,.3); }
              .summary-content { color: #ebebf0; }
              .step { background: #2c2c2e; box-shadow: 0 1px 3px rgba(0,0,0,.3); }
              .step-header { background: #3a3a3c; }
              .step-num { color: #636366; }
              .coord { color: #636366; }
              .step-obs-col { color: #ebebf0; }
            }
          </style>
          </head>
          <body>
          <div class="header">
            <h1>${lbl.title}</h1>
            <div class="objective">${report.objective.htmlEscape()}</div>
            <div class="meta">${report.stepCount} ${lbl.steps} &middot; $durationText</div>
            $personaCardHtml
          </div>
          <div class="summary-box">
            <h2>${lbl.summary}</h2>
            <div class="summary-content">${report.summary.renderSummaryMarkdown()}</div>
          </div>
          <div class="steps">
            <h2>${lbl.stepByStep}</h2>
            $stepsHtml
          </div>
          </body>
          </html>
          """.trimIndent()
      }

      // Parses [CRITICAL]/[ISSUE]/[POSITIVE] prefix into a colored badge.
      // Falls back to plain escaped text if no prefix is found.
      private fun renderObservation(obs: String): String {
          val (badge, text) = when {
              obs.startsWith("[CRITICAL]") ->
                  """<span class="badge badge-critical">CRITICAL</span>""" to obs.removePrefix("[CRITICAL]").trim()
              obs.startsWith("[ISSUE]") ->
                  """<span class="badge badge-issue">ISSUE</span>""" to obs.removePrefix("[ISSUE]").trim()
              obs.startsWith("[POSITIVE]") ->
                  """<span class="badge badge-positive">POSITIVE</span>""" to obs.removePrefix("[POSITIVE]").trim()
              else -> "" to obs
          }
          return "$badge${text.htmlEscape()}"
      }

      // Converts **bold** and - bullets to HTML, line by line.
      private fun String.renderSummaryMarkdown(): String {
          val lines = this.split("\n")
          val out = StringBuilder()
          var inList = false
          for (line in lines) {
              when {
                  line.startsWith("- ") -> {
                      if (!inList) { out.append("<ul>"); inList = true }
                      val content = line.removePrefix("- ").htmlEscape().renderBold()
                      out.append("<li>$content</li>")
                  }
                  line.isBlank() -> {
                      if (inList) { out.append("</ul>"); inList = false }
                  }
                  else -> {
                      if (inList) { out.append("</ul>"); inList = false }
                      out.append("<p>${line.htmlEscape().renderBold()}</p>")
                  }
              }
          }
          if (inList) out.append("</ul>")
          return out.toString()
      }

      private fun String.renderBold(): String =
          replace(Regex("\\*\\*(.+?)\\*\\*"), "<strong>$1</strong>")

      private fun ByteArray.imageMimeType(): String = when {
          size >= 2 && this[0] == 0xFF.toByte() && this[1] == 0xD8.toByte() -> "image/jpeg"
          else -> "image/png"
      }

      private fun String.htmlEscape(): String = this
          .replace("&", "&amp;")
          .replace("<", "&lt;")
          .replace(">", "&gt;")
          .replace("\"", "&quot;")

      private fun fmtDuration(ms: Long): String {
          val sec = ms / 1000
          val dec = (ms % 1000) / 100
          return "${sec}.${dec}s"
      }

      private fun fmtCoord(v: Double): String {
          val rounded = kotlin.math.round(v * 100).toInt()
          val intPart = rounded / 100
          val decPart = rounded % 100
          return "$intPart.${decPart.toString().padStart(2, '0')}"
      }
  }
  ```

- [ ] **Step 2: Verify Kotlin compiles**

  ```bash
  cd sdk && ./gradlew testpilot:compileKotlinMetadata
  ```

  Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

  ```bash
  git add sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/HtmlReportWriter.kt
  git commit -m "feat(sdk): persona card, severity badges, markdown rendering in HTML report"
  ```

---

### Task 5: CLI — `--persona` flag + base64 pass-through + generated Swift

**Files:**
- Modify: `testpilot` (bash script at repo root)

The `testpilot` bash script has three sections to modify:
1. Argument parsing (`--persona` flag, after line ~44)
2. Validation (persona file must exist)
3. Generated analyze Swift (read persona from env, add to ConfigBuilder)
4. xcodebuild call (add `-testenv TESTPILOT_PERSONA_B64=...`)

- [ ] **Step 1: Add `--persona` to argument parsing**

  Locate the argument parsing block (around line 44 where `--objective` is parsed). Add after `--objective`:

  ```bash
  --persona)  PERSONA_FILE="$2"; shift 2 ;;
  ```

- [ ] **Step 2: Add persona file validation**

  Locate the validation block (around line 141 where `--objective required` check is). Add after it:

  ```bash
  if [[ -n "$PERSONA_FILE" ]] && [[ ! -f "$PERSONA_FILE" ]]; then
      echo "Error: persona file not found: $PERSONA_FILE"
      exit 1
  fi
  ```

- [ ] **Step 3: Add persona to the `CREDENTIALS_BLOCK` pattern**

  Locate `CREDENTIALS_BLOCK='` (around line 278). Add a `PERSONA_BLOCK` variable right after `CREDENTIALS_BLOCK`:

  ```bash
  PERSONA_BLOCK='        let persona: String? = nil'
  if [[ -n "$PERSONA_FILE" ]]; then
      PERSONA_BLOCK='        let personaB64 = env["TESTPILOT_PERSONA_B64"]
          let persona: String? = personaB64.flatMap { Data(base64Encoded: $0) }
              .flatMap { String(data: $0, encoding: .utf8) }'
  fi
  ```

- [ ] **Step 4: Update the analyze Swift template to read persona and pass to ConfigBuilder**

  In the analyze branch of the Swift heredoc (the `else` branch of `if [[ "$TEST_MODE" == "true" ]]`), locate the `ConfigBuilder()` chain:

  ```swift
          let config = ConfigBuilder()
              .provider(provider: provider)
              .apiKey(key: apiKey)
              .maxSteps(steps: $MAX_STEPS)
              .language(lang: "$LANG_ESC")
              .build()
  ```

  Replace with (note the added `.persona(markdown: persona)`):

  ```bash
  cat > "$TEST_SWIFT" <<SWIFT
  // This file is overwritten by the testpilot CLI before each run.
  // Do not edit manually.
  import XCTest
  import TestPilotShared

  class AnalystTests: XCTestCase {
      var analyst: AnalystIOS!
      var xcApp: XCUIApplication!

      override func setUp() {
          super.setUp()
          xcApp = $XCAPP_INIT
          let provider: AIProvider = "$PROVIDER_ESC" == "openai" ? .openai : ("$PROVIDER_ESC" == "gemini" ? .gemini : .anthropic)
  $CREDENTIALS_BLOCK
  $PERSONA_BLOCK
          let config = ConfigBuilder()
              .provider(provider: provider)
              .apiKey(key: apiKey)
              .maxSteps(steps: $MAX_STEPS)
              .language(lang: "$LANG_ESC")
              .persona(markdown: persona)
              .build()
          analyst = AnalystIOS(config: config)
      }

      func testAnalyze() async throws {
          let _ = try await analyst.run(
              objective: "$OBJECTIVE_ESC",
              xcApp: xcApp,
              username: username,
              password: password
          )
      }
  }
  SWIFT
  ```

  The test mode (`TEST_MODE == "true"`) Swift template is **not** changed — persona is analyze-only.

- [ ] **Step 5: Add `-testenv TESTPILOT_PERSONA_B64` to the xcodebuild call**

  Locate the block where `-testenv` args are appended (around line 369):

  ```bash
  XCODE_EXTRA_ARGS+=(-testenv "TESTPILOT_API_KEY=$API_KEY")
  [[ -n "$USERNAME" ]] && XCODE_EXTRA_ARGS+=(-testenv "TESTPILOT_USERNAME=$USERNAME")
  [[ -n "$PASSWORD" ]] && XCODE_EXTRA_ARGS+=(-testenv "TESTPILOT_PASSWORD=$PASSWORD")
  ```

  Add after:

  ```bash
  if [[ -n "$PERSONA_FILE" ]] && [[ "$TEST_MODE" != "true" ]]; then
      PERSONA_B64=$(base64 < "$PERSONA_FILE")
      XCODE_EXTRA_ARGS+=(-testenv "TESTPILOT_PERSONA_B64=$PERSONA_B64")
  fi
  ```

- [ ] **Step 6: Verify the script parses correctly**

  ```bash
  bash -n ./testpilot
  ```

  Expected: no output (syntax is valid)

- [ ] **Step 7: Commit**

  ```bash
  git add testpilot
  git commit -m "feat(cli): add --persona flag to analyze subcommand"
  ```

---

### Task 6: Mac app — RunConfig + RunView (file picker UI)

**Files:**
- Modify: `mac-app/TestPilotApp/Models/RunConfig.swift`
- Modify: `mac-app/TestPilotApp/Views/RunView.swift`

- [ ] **Step 1: Add `personaPath` to `RunConfig`**

  In `RunConfig.swift`, add after `var outputPath`:

  ```swift
  var personaPath: String = ""

  /// Returns the persona markdown content, or nil if no persona is set.
  var personaContent: String? {
      guard !personaPath.isEmpty else { return nil }
      let expanded = NSString(string: personaPath).expandingTildeInPath
      return try? String(contentsOfFile: expanded, encoding: .utf8)
  }
  ```

- [ ] **Step 2: Add persona file picker to `RunView`**

  In `RunView.swift`, inside `Section("Required")`, add the persona picker block right before the closing `}` of the section (after the `Manage Session` button block). It must be wrapped in `if config.mode == .analyze`:

  ```swift
  if config.mode == .analyze {
      HStack {
          if config.personaPath.isEmpty {
              Text("No persona")
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
          } else {
              Text(URL(fileURLWithPath: config.personaPath).lastPathComponent)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .lineLimit(1)
              Button {
                  config.personaPath = ""
              } label: {
                  Image(systemName: "xmark.circle.fill")
                      .foregroundStyle(.secondary)
              }
              .buttonStyle(.borderless)
              .help("Remove persona")
          }
          Button("Persona…") {
              let panel = NSOpenPanel()
              panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .text]
              panel.allowsMultipleSelection = false
              panel.canChooseDirectories = false
              panel.title = "Choose Persona File"
              if panel.runModal() == .OK, let url = panel.url {
                  config.personaPath = url.path
              }
          }
          .buttonStyle(.bordered)
      }
  }
  ```

  Also add `import UniformTypeIdentifiers` at the top of `RunView.swift` if it isn't already there (needed for `UTType`).

- [ ] **Step 3: Build Mac app in Xcode**

  Open `mac-app/TestPilot.xcodeproj`, select `TestPilotApp` scheme, press `Cmd+B`.

  Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

  ```bash
  git add mac-app/TestPilotApp/Models/RunConfig.swift \
          mac-app/TestPilotApp/Views/RunView.swift
  git commit -m "feat(mac): add persona file picker to RunConfig and RunView"
  ```

---

### Task 7: Mac app IOSRunner — persona in generated Swift + `-testenv`

**Files:**
- Modify: `mac-app/TestPilotApp/Services/IOSRunner.swift`

Two changes: pass `TESTPILOT_PERSONA_B64` via `-testenv` in `makeProcess()`, and read it in the generated Swift in `buildTestSwift()`.

- [ ] **Step 1: Add persona `-testenv` arg in `makeProcess()`**

  In `makeProcess()`, after the password `-testenv` block (lines 108–110):

  ```swift
  if !config.password.isEmpty {
      args += ["-testenv", "TESTPILOT_PASSWORD=\(config.password)"]
  }
  ```

  Add:

  ```swift
  // Persona is only used in analyze mode
  if config.mode == .analyze, let personaContent = config.personaContent,
     let personaData = personaContent.data(using: .utf8) {
      args += ["-testenv", "TESTPILOT_PERSONA_B64=\(personaData.base64EncodedString())"]
  }
  ```

- [ ] **Step 2: Add persona reading block to `buildTestSwift()`**

  In `buildTestSwift()`, after the `credentialsBlock` constant, add:

  ```swift
  let personaBlock: String
  if config.mode == .analyze && config.personaContent != nil {
      personaBlock = """
              let personaB64 = env["TESTPILOT_PERSONA_B64"]
              let persona: String? = personaB64.flatMap { Data(base64Encoded: $0) }
                  .flatMap { String(data: $0, encoding: .utf8) }
      """
  } else {
      personaBlock = "        let persona: String? = nil"
  }
  ```

- [ ] **Step 3: Add `personaBlock` and `.persona(markdown: persona)` to the analyze Swift template**

  In `buildTestSwift()`, the analyze `else` branch currently generates:

  ```swift
  \(credentialsBlock)
          let config = ConfigBuilder()
              .provider(provider: provider)
              .apiKey(key: apiKey)
              .maxSteps(steps: \(maxSteps))
              .language(lang: "\(langEsc)")
              .build()
  ```

  Replace with:

  ```swift
  \(credentialsBlock)
  \(personaBlock)
          let config = ConfigBuilder()
              .provider(provider: provider)
              .apiKey(key: apiKey)
              .maxSteps(steps: \(maxSteps))
              .language(lang: "\(langEsc)")
              .persona(markdown: persona)
              .build()
  ```

  The test mode template is unchanged.

- [ ] **Step 4: Build Mac app in Xcode**

  Open `mac-app/TestPilot.xcodeproj`, select `TestPilotApp` scheme, press `Cmd+B`.

  Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

  ```bash
  git add mac-app/TestPilotApp/Services/IOSRunner.swift
  git commit -m "feat(mac): pass persona to generated Swift via -testenv in IOSRunner"
  ```

---

### Task 8: Final push and tag

- [ ] **Step 1: Push all commits**

  ```bash
  git push
  ```

- [ ] **Step 2: Tag v0.1.15**

  ```bash
  git tag v0.1.15 && git push origin v0.1.15
  ```

---

## Self-Review

**Spec coverage:**
- ✅ `personaMarkdown: String?` in Config + ConfigBuilder `persona()` method — Task 1
- ✅ VisionPrompt persona section injection — Task 2
- ✅ Analyst propagates persona to AnalysisReport + generateSummary — Task 3
- ✅ HtmlReportWriter: persona card, severity badges, markdown rendering — Task 4
- ✅ CLI `--persona` flag + base64 pass-through + generated Swift — Task 5
- ✅ Mac app RunConfig `personaPath` + `personaContent` computed property — Task 6
- ✅ Mac app RunView file picker (analyze mode only) — Task 6
- ✅ Mac app IOSRunner `-testenv` + generated Swift persona block — Task 7
- ✅ WebRunner not covered — WebRunner passes args to the JAR; persona support for web would require a separate JAR-side change. Left as a non-goal per spec.
- ✅ Test mode unaffected throughout

**Placeholder scan:** No TBD/TODO found.

**Type consistency:**
- `personaMarkdown: String?` — used in Config (Task 1), VisionPrompt (Task 2), Analyst (Task 3) ✅
- `persona: String?` — used in AnalysisReport (Task 1), HtmlReportWriter `report.persona` (Task 4) ✅
- `personaPath: String` / `personaContent: String?` — used in RunConfig (Task 6), IOSRunner (Task 7) ✅
- `.persona(markdown: persona)` ConfigBuilder call — matches `func persona(markdown: String?)` defined in Task 1 ✅
- `renderObservation()` — defined and called in Task 4 only ✅
- `renderSummaryMarkdown()` / `renderBold()` — defined and called in Task 4 only ✅

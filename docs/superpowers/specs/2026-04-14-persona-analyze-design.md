# Persona Support for Exploratory Analysis — Design

**Date:** 2026-04-14
**Status:** Approved

---

## Goal

Allow users to supply a free-form persona profile (`.md` file) that shapes how the AI explores the app in analyze mode — which flows it prioritizes, what friction it notices, and how the final report is framed. Test mode is unaffected.

## Architecture

A `personaMarkdown: String?` field flows from user input → `Config` → `VisionPrompt` (system prompt injection) → `AnalysisReport` → `HtmlReportWriter` (persona card + severity colors + markdown rendering). No new abstraction layers; the persona is just context added at the prompt and report layers.

**Affected subsystems:** Kotlin SDK (Config, VisionPrompt, Analyst, AnalysisReport, HtmlReportWriter), CLI bash script, Mac app (RunConfig, RunView, AnalysisRunner).

---

## File Structure

| Action | File |
|--------|------|
| Modify | `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/AnalysisReport.kt` |
| Modify | `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/runtime/Config.kt` |
| Modify | `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/ai/VisionPrompt.kt` |
| Modify | `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/Analyst.kt` |
| Modify | `sdk/testpilot/src/commonMain/kotlin/co/work/testpilot/analyst/HtmlReportWriter.kt` |
| Modify | `testpilot` (CLI bash script) |
| Modify | `mac-app/TestPilotApp/Models/RunConfig.swift` |
| Modify | `mac-app/TestPilotApp/Views/RunView.swift` |
| Modify | `mac-app/TestPilotApp/Services/AnalysisRunner.swift` |

---

## Detailed Design

### 1. Kotlin SDK — `AnalysisReport.kt`

Add optional `persona` field:

```kotlin
data class AnalysisReport(
    val objective: String,
    val summary: String,
    val stepCount: Int,
    val durationMs: Long,
    val steps: List<AnalysisStep>,
    val persona: String? = null,
)
```

### 2. Kotlin SDK — `Config.kt`

Add `personaMarkdown: String? = null` to the `Config` data class and a `persona()` builder method:

```kotlin
data class Config(
    // ... existing fields ...
    val personaMarkdown: String? = null,
)
```

In `ConfigBuilder`:

```kotlin
var personaMarkdown: String? = null

fun persona(markdown: String?): ConfigBuilder {
    this.personaMarkdown = markdown
    return this
}

fun build(): Config = Config(
    // ... existing fields ...
    personaMarkdown = personaMarkdown,
)
```

### 3. Kotlin SDK — `VisionPrompt.kt`

Inject persona section into the system prompt when `config.personaMarkdown` is not null:

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
        """
    } ?: ""
```

Append `personaSection` to the system prompt string, after the existing navigation rules block.

### 4. Kotlin SDK — `Analyst.kt`

Two changes:

**a) Propagate persona to `AnalysisReport`:**

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

**b) Frame `generateSummary` with the persona when present:**

```kotlin
val personaContext = if (config.personaMarkdown.isNullOrBlank()) "" else """

This evaluation was conducted from the perspective of:
<persona>
${config.personaMarkdown}
</persona>

Frame your findings through the lens of this persona's goals and pain points.
"""
```

Append `personaContext` to the summary prompt string.

### 5. Kotlin SDK — `HtmlReportWriter.kt`

Three changes:

**a) Persona card** — rendered after the objective in the header when `report.persona != null`:

```html
<div class="persona-card">
  <span class="persona-icon">👤</span>
  <div class="persona-content">
    <div class="persona-label">Evaluated as</div>
    <div class="persona-text">${personaFirstLine}</div>
  </div>
</div>
```

`personaFirstLine` is the first non-blank line of the persona markdown (gives a quick identifier without dumping the full content). A "Show full persona" `<details>` element below it reveals the rest.

CSS additions:
```css
.persona-card { display: flex; gap: 10px; align-items: flex-start; margin-top: 12px;
                background: #f2f2f7; border-radius: 8px; padding: 10px 14px; }
.persona-label { font-size: 11px; color: #8e8e93; text-transform: uppercase;
                 letter-spacing: .04em; }
.persona-text  { font-size: 13px; font-weight: 500; margin-top: 2px; }
.persona-full  { font-size: 12px; color: #6e6e73; margin-top: 6px;
                 white-space: pre-wrap; line-height: 1.5; }
```

Dark mode additions:
```css
.persona-card  { background: #3a3a3c; }
.persona-text  { color: #f5f5f7; }
.persona-full  { color: #aeaeb2; }
```

**b) Severity coloring on step observations**

The `VisionPrompt` produces observations prefixed with `[CRITICAL]`, `[ISSUE]`, or `[POSITIVE]`. The report strips the prefix, replaces it with a colored badge, and styles the observation text:

```kotlin
private fun renderObservation(obs: String): String {
    val (badge, text) = when {
        obs.startsWith("[CRITICAL]") -> """<span class="badge badge-critical">CRITICAL</span>""" to obs.removePrefix("[CRITICAL]").trim()
        obs.startsWith("[ISSUE]")    -> """<span class="badge badge-issue">ISSUE</span>"""    to obs.removePrefix("[ISSUE]").trim()
        obs.startsWith("[POSITIVE]") -> """<span class="badge badge-positive">POSITIVE</span>""" to obs.removePrefix("[POSITIVE]").trim()
        else                         -> "" to obs
    }
    return """<p>$badge ${text.htmlEscape()}</p>"""
}
```

CSS:
```css
.badge         { display: inline-block; font-size: 10px; font-weight: 700; letter-spacing: .06em;
                 padding: 1px 6px; border-radius: 3px; margin-right: 6px; vertical-align: middle; }
.badge-critical { background: #ff3b30; color: #fff; }
.badge-issue    { background: #ff9500; color: #fff; }
.badge-positive { background: #34c759; color: #fff; }
```

**c) Basic markdown rendering for the summary**

The structured summary from `generateSummary` uses `**bold**` and `- bullets`. Convert these before HTML-escaping:

```kotlin
private fun String.renderSummaryMarkdown(): String {
    // Process line by line to avoid multiline regex edge cases
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
                out.append("<br>")
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
```

Used in the summary box:
```kotlin
<div class="summary-box">
  <h2>${lbl.summary}</h2>
  <div class="summary-content">${report.summary.renderSummaryMarkdown()}</div>
</div>
```

Add CSS:
```css
.summary-content ul { padding-left: 18px; margin: 6px 0; }
.summary-content li { font-size: 14px; color: #3a3a3c; margin-bottom: 4px; }
.summary-content strong { font-weight: 600; }
```

---

### 6. CLI — `testpilot` bash script

**Parsing:** Add `--persona` to the `analyze` subcommand argument parsing (not `test`):

```bash
--persona) PERSONA_FILE="$2"; shift 2 ;;
```

Validate after parsing (analyze only):
```bash
if [[ -n "$PERSONA_FILE" ]] && [[ ! -f "$PERSONA_FILE" ]]; then
    echo "Error: persona file not found: $PERSONA_FILE"; exit 1
fi
```

**Passing persona content:** Persona markdown is multi-line, so it is base64-encoded before passing via `-testenv`:

```bash
if [[ -n "$PERSONA_FILE" ]]; then
    PERSONA_B64=$(base64 < "$PERSONA_FILE")
    XCODE_EXTRA_ARGS+=(-testenv "TESTPILOT_PERSONA_B64=$PERSONA_B64")
fi
```

**Generated Swift (analyze branch only):** Add a persona block to the `CREDENTIALS_BLOCK`-style section:

```swift
let personaB64 = env["TESTPILOT_PERSONA_B64"]
let persona: String? = personaB64.flatMap { Data(base64Encoded: $0) }
    .flatMap { String(data: $0, encoding: .utf8) }
```

Then add `.persona(markdown: persona)` to the `ConfigBuilder` chain in the analyze Swift template.

---

### 7. Mac app — `RunConfig.swift`

```swift
var personaPath: String = ""

var personaContent: String? {
    guard !personaPath.isEmpty else { return nil }
    return try? String(contentsOfFile: NSString(string: personaPath).expandingTildeInPath, encoding: .utf8)
}
```

### 8. Mac app — `RunView.swift`

Add a persona row in the `Section("Required")` block, visible only when `config.mode == .analyze`:

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
            Button {
                config.personaPath = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        Button("Choose…") {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .text]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            if panel.runModal() == .OK, let url = panel.url {
                config.personaPath = url.path
            }
        }
        .buttonStyle(.bordered)
    }
}
```

### 9. Mac app — `AnalysisRunner.swift`

No change needed — `RunConfig.personaContent` is a computed property that reads the file lazily. The persona content is passed to the runner via whichever platform runner (IOSRunner, WebRunner) through `config`.

Each platform runner reads `config.personaContent` and appends `.persona(markdown: config.personaContent)` to the `ConfigBuilder` call in the generated Swift or web args.

**WebRunner** appends `--persona-b64 <base64>` to the JAR command-line args when persona is present (the web JAR already reads other config from args; persona follows the same pattern):

```swift
if let content = config.personaContent,
   let data = content.data(using: .utf8) {
    args += ["--persona-b64", data.base64EncodedString()]
}
```

The web JAR's `main()` decodes and passes it to `ConfigBuilder.persona()`.

**IOSRunner** passes persona via `-testenv` the same way as CLI:

```swift
if let content = config.personaContent,
   let data = content.data(using: .utf8) {
    let b64 = data.base64EncodedString()
    args += ["-testenv", "TESTPILOT_PERSONA_B64=\(b64)"]
}
```

The generated `AnalystTests.swift` reads it the same way as the CLI template.

---

## Behavior Summary

| Scenario | Behavior |
|----------|----------|
| No persona | Exploration works exactly as today |
| Persona provided | AI navigates and observes from persona's perspective; report shows persona card |
| Persona + analyze | Full experience: persona-scoped exploration + structured report + severity badges |
| Test mode | Persona field ignored entirely; test mode unaffected |
| Missing persona file | Error at startup with clear message |

---

## Non-Goals

- Persona support in test mode
- Multiple personas per run
- Parsing/validating persona file structure
- Persona templates or built-in examples

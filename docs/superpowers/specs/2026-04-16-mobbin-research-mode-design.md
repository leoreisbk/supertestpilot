# Research Mode — Mobbin Integration Design

**Date:** 2026-04-16
**Status:** Approved

---

## Overview

Add a third run mode — **Research** — to TestPilot. Where Analyze runs against your live app and Test validates pass/fail conditions, Research pulls reference screens from Mobbin and produces a competitive UX report. The output is the same HTML report format, reframed as a competitive brief for PMs and designers.

---

## Architecture

Three layers of change, cleanly separated. No existing modes (Analyze, Test) are touched.

```
CLI / macOS app
    └── testpilot research subcommand / Research RunMode
            │
            ▼
    MobbinFetcher (bash layer)
    Calls Mobbin's internal API using saved session cookies
    Returns ordered list of PNG images for the flow
            │
            ▼ List<ByteArray>
            │
    MobbinAnalyst (new — commonMain)
    Iterates images sequentially, no interaction
    Calls ResearchVisionPrompt per image
    Calls generateSummary with all observations + all images
            │
            ▼
    HtmlReportWriter (minimal change)
    Same HTML report, "Research Report" header
```

---

## Authentication

Mobbin requires a logged-in session. Auth is scoped separately from web app sessions.

- **CLI:** `testpilot mobbin-login` — opens a browser, user logs in to mobbin.com, cookies saved to `~/.testpilot/mobbin/cookies`. Same browser-login mechanism as `web-login`.
- **macOS app:** "Connect Mobbin…" button in Research mode — same login sheet pattern as "Manage Session…" in web mode. Label updates to "Mobbin Connected ✓" once a valid session is saved.
- **Session reuse:** `MobbinFetcher` reads cookies from `~/.testpilot/mobbin/cookies` on every run. If the session has expired, the CLI exits with: `"Mobbin session expired — run: testpilot mobbin-login"`.

---

## Data Flow

```
1. User provides: flow URL  OR  (app name + flow name)
       │
       ▼
2. MobbinFetcher (bash)
   - Flow URL  → extract flow ID → GET /api/content/flows/:id
   - App+Flow  → GET /api/content/search-apps → GET /api/content/search-flows
   - Download all flow images as PNGs to a temp dir
   - Output: ordered list of local PNG file paths
       │
       ▼  paths → platform entry point → MobbinAnalyst
       │
3. MobbinAnalyst.run(images, objective, onStep)
   - For each image:
       → ResearchVisionPrompt(objective, imageBytes, observationsSoFar)
       → collect observation (no action parsing needed)
       → onStep(observation) for live progress
   - After all images:
       → generateSummary(objective, allSteps)
         (text-only: sends all observations in one final prompt — same as Analyst.generateSummary)
       │
       ▼
4. HtmlReportWriter → report.html
```

---

## New SDK Components

### `MobbinAnalyst` (`commonMain/analyst/MobbinAnalyst.kt`)

```kotlin
class MobbinAnalyst(
    private val aiClient: AIClient,
    private val config: Config,
) {
    suspend fun run(
        images: List<ByteArray>,
        objective: String,
        onStep: ((String) -> Unit)? = null,
    ): AnalysisReport
}
```

- Takes images as `List<ByteArray>` — no `AnalystDriver`, no interaction logic, no stuckCount
- Uses `ResearchVisionPrompt` instead of `VisionPrompt`
- `generateSummary` logic extracted from `Analyst` into a shared internal function in `commonMain/analyst/`
- Report tagged with `source = "mobbin"` so `HtmlReportWriter` renders "Research Report" header

### `ResearchVisionPrompt` (`commonMain/ai/ResearchVisionPrompt.kt`)

Frames the AI as a competitive UX analyst reviewing reference screens from a competitor app.

**System prompt framing:**
> You are a competitive UX analyst. You are reviewing screens from a competitor app. Your job is to identify design patterns, decisions, and UX strategies that give this app an advantage or disadvantage — and what a product team can learn from them.

**Per-screen focus:**
- Design decisions: information hierarchy, onboarding hooks, empty states, social proof, conversion nudges
- Patterns worth adopting
- Weaknesses that represent exploitable gaps

**Severity tags (replaces CRITICAL/ISSUE/POSITIVE):**
- `[ADVANTAGE]` — strong pattern the competitor is using well
- `[WEAKNESS]` — exploitable gap or poor decision
- `[PATTERN]` — neutral design decision worth noting

**Persona lens:** If `config.personaMarkdown` is set, observations are filtered through that persona's goals and pain points.

**Response JSON:** Simplified — no action/coordinates needed:
```json
{ "observation": "..." }
```

**Summary output:** A competitive brief — not "fix this" but "here's what they do well, here's where you can win, here's what to prioritize."

---

## CLI Changes

New subcommand: `testpilot research`

```bash
# By flow URL
testpilot research --flow <mobbin-flow-url> [--objective <text>] [--persona <file>]

# By search
testpilot research --app "Nike Run Club" --flow-name "Onboarding" [--objective <text>] [--persona <file>]

# Auth
testpilot mobbin-login
```

Shared flags: `--provider`, `--api-key`, `--max-steps`, `--output`, `--lang`

---

## macOS App Changes

### `RunMode` enum

```swift
enum RunMode: String, Codable, CaseIterable, Identifiable {
    case analyze
    case test
    case research
    var displayName: String {
        switch self {
        case .analyze:  return "Analyze"
        case .test:     return "Test"
        case .research: return "Research"
        }
    }
}
```

### `RunView` — Research mode form

When `config.mode == .research`:
- Platform picker hidden (not applicable)
- Device picker hidden
- Source toggle: `[Flow URL | Search]` segmented control
  - **Flow URL** selected: single Mobbin URL text field
  - **Search** selected: App name + Flow name text fields
- **Objective** — optional (persona can define focus)
- **Connect Mobbin…** button — triggers browser login sheet, same as "Manage Session…"
- **Persona…** picker — same as Analyze mode
- **Run Research** CTA button

### `RunConfig` additions

```swift
var mobbinFlowUrl: String = ""
var mobbinAppName: String = ""
var mobbinFlowName: String = ""
```

`isValid` for research mode: `~/.testpilot/mobbin/cookies` file exists AND (flow URL is non-empty OR both app name + flow name are non-empty).

---

## What Is Not Changed

- `Analyst`, `TestAnalyst`, `AnalystDriver` — untouched
- `VisionPrompt`, `TestVisionPrompt` — untouched
- `HtmlReportWriter` — minimal change: reads `source` field to set report title
- `Config`, `ConfigBuilder` — untouched
- All existing Analyze and Test flows — unaffected

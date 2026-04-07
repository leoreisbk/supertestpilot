# TestPilot Vision Analyst — Design Spec
**Date:** 2026-04-07
**Status:** Approved
**Branch:** feat/claude-support

---

## Overview

TestPilot gains a second mode alongside the existing test runner: an **AI UX Analyst**. Instead of pass/fail assertions, the Analyst navigates an app, reasons visually about what it sees, and produces a human-readable report on usability and friction.

The target user is a **PM or designer** who wants to benchmark an experience without writing code. They download the repo, run one terminal command, and get an HTML report.

---

## Architecture

Two distinct layers share one platform foundation:

```
┌─────────────────────────────────────────┐
│           Analyst  (NEW)                │
│   AnalystLoop → VisionPrompt → Report   │
├─────────────────────────────────────────┤
│      Interaction Engine  (existing)     │
│  screenshot() │ tap(x,y) │ scroll()    │
├──────────────┬──────────────────────────┤
│     iOS      │        Android           │
│ XCUIAutomation│     UIAutomator         │
└──────────────┴──────────────────────────┘
```

The existing `Runner` / `TestActor` / `Instruction` stack is **not modified**. The Analyst is a parallel path that talks to the interaction engine through a new coordinate-based action layer.

---

## The Analysis Loop

Each iteration:

1. Capture a screenshot
2. Send to AI: screenshot (base64 PNG) + objective + observations collected so far
3. AI responds with a single JSON:
   ```json
   {
     "action": "tap",
     "x": 0.72,
     "y": 0.45,
     "observation": "Cart icon is small and placed top-right, easy to miss on first visit",
     "reason": "navigating to cart"
   }
   ```
4. Log the observation, execute the action
5. Repeat until `action: "done"` or `maxSteps` is reached
6. AI generates a final summary from all collected observations

### Action types

| Action | Parameters | Description |
|--------|-----------|-------------|
| `tap` | `x`, `y` (0.0–1.0) | Tap at relative screen coordinates |
| `scroll` | `direction` (up/down) | Scroll the current screen |
| `type` | `x`, `y`, `text` | Tap a field then type text |
| `done` | — | Objective complete, generate report |

Coordinates are **relative (0.0–1.0)** so they work across all screen sizes and devices.

### AI reasoning

The AI receives no predefined observation categories. It reasons freely from what it sees in the screenshot — noting friction, confusing layouts, missing affordances, or anything relevant to the objective. Observations are free text.

---

## Report

### Data model

```
AnalysisReport
├── objective: String
├── summary: String          (AI-generated paragraph at the end)
├── stepCount: Int
├── durationMs: Long
└── steps: List<AnalysisStep>
    ├── screenshotData: ByteArray   (PNG at this moment)
    ├── observation: String?        (what the AI noticed, can be null)
    ├── action: String              (what it did)
    └── coordinates: Pair<Double, Double>?
```

### HTML output

An `AnalysisReport.html` file is generated automatically in the current working directory. It contains:

- Summary paragraph at the top
- Step-by-step timeline with screenshots and observations
- Total steps and duration

No external dependencies — the HTML file is self-contained and shareable.

---

## CLI

Entry point for PMs. Located at `./testpilot` in the repo root.

```bash
./testpilot analyze \
  --platform ios \
  --app "MyApp" \
  --objective "analyze how easy it is to complete a checkout"
```

```bash
./testpilot analyze \
  --platform android \
  --app "MyApp" \
  --objective "explore the onboarding flow and report friction"
```

### App name resolution

The `--app` flag accepts the **human-readable app name**, not a bundle ID or package name. The script resolves it behind the scenes:

- **iOS:** `xcrun simctl list apps` — searches installed apps on the active simulator
- **Android:** `adb shell pm list packages -3` + app label lookup via `aapt`

If more than one match is found, the script lists them and asks the PM to pick.

### API key

Passed via flag or `.env` file:

```bash
# .env (set once, never typed again)
TESTPILOT_API_KEY=sk-ant-...
TESTPILOT_PROVIDER=anthropic   # or openai
```

### What the script does

1. Validates platform tools are available (Xcode / ADB)
2. Verifies a simulator or device is connected
3. Resolves app name → bundle ID / package name
4. Builds and runs the analysis bundle silently
5. Writes `report.html` to the current directory
6. Opens the report in the default browser

### Flags

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--platform` | yes | — | `ios` or `android` |
| `--app` | yes | — | App display name |
| `--objective` | yes | — | What to analyze |
| `--api-key` | no | `$TESTPILOT_API_KEY` | AI provider key |
| `--provider` | no | `anthropic` | `anthropic` or `openai` |
| `--max-steps` | no | `20` | Max navigation steps |
| `--output` | no | `./report.html` | Report output path |

---

## New files

```
sdk/testpilot/src/
  commonMain/
    ai/
      VisionPrompt.kt          ← new vision-aware prompt
    analyst/
      Analyst.kt               ← main loop
      AnalysisReport.kt        ← data model
      AnalysisStep.kt
      HtmlReportWriter.kt      ← generates report.html
  iosMain/
    analyst/
      AnalystIOS.kt            ← iOS coordinator
  androidMain/
    analyst/
      AnalystAndroid.kt        ← Android coordinator

testpilot  (repo root)         ← CLI entry point (bash script)
```

---

## What is NOT changing

- The existing `automate()` / `Runner` / `TestActor` / `Instruction` stack — untouched
- The `Config` / `ConfigBuilder` API — reused as-is
- The `AnthropicChatClient` and `OpenAIChatClient` — extended to support image input, not replaced

---

## Open questions

- Screenshot capture on iOS requires `XCUIScreen` to be added to the cinterop stub — already verified it exists in `XCUIAutomation.framework`
- Android screenshot capture via `UiDevice.takeScreenshot(File)` — standard UIAutomator API, no extra dependencies
- The CLI script targets macOS (bash). Windows/Linux support is out of scope for now.

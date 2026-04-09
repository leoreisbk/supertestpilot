# Test Mode Design

**Date:** 2026-04-09
**Status:** Approved

---

## Overview

TestPilot today supports one mode: exploratory analysis (`./testpilot analyze`). This spec adds a second mode, `./testpilot test`, for deterministic, pass/fail test assertions driven by the same vision-based AI loop — but with caching, explicit verdicts, and CI-friendly exit codes.

---

## Problem

Exploratory analysis is non-deterministic by design: each run follows a different path. That makes it unsuitable for regression testing, where you want to run the same test repeatedly and get a stable, binary result. A QA engineer who writes "check if the Buy button is enabled" needs a `PASS`/`FAIL` answer, not an exploration report.

---

## Goals

- Add `./testpilot test` subcommand with deterministic, cached, pass/fail semantics
- Keep `./testpilot analyze` unchanged (no breaking changes)
- Show real-time step progress in terminal and macOS app
- Enable CI integration via exit codes (`0` = PASS, `1` = FAIL)
- Cache identical screenshot+prompt pairs to reduce token cost on reruns

---

## Architecture

Two runtimes, same AI loop:

| | `analyze` | `test` |
|---|---|---|
| Subcommand | `./testpilot analyze` | `./testpilot test` |
| iOS class | `AnalystIOS` | `TestAnalystIOS` |
| Common loop | `Analyst` | `TestAnalyst` |
| Prompt | `AnalysisVisionPrompt` | `TestVisionPrompt` |
| Output | HTML report | PASS/FAIL + steps |
| Cache | No | Yes (`~/.testpilot/cache/`) |
| Exit code | Always 0 | 0 = PASS, 1 = FAIL |
| HTML report | Yes | No |

---

## SDK Layer

### `TestVisionPrompt`

System prompt instructs the model to act as a deterministic test evaluator:
- Each step: describe what is visible and decide the next action
- When enough evidence exists: return `Pass(reason)` or `Fail(reason)`
- No exploration — terminate as soon as verdict is clear

### `AnalysisAction` extensions

Add two new sealed subclasses to `AnalysisAction`:

```kotlin
sealed class AnalysisAction {
    // existing actions...
    data class Pass(val reason: String) : AnalysisAction()
    data class Fail(val reason: String) : AnalysisAction()
}
```

### `TestResult`

```kotlin
data class TestResult(
    val passed: Boolean,
    val reason: String,
    val steps: List<String>,
)
```

### `TestAnalyst`

Mirrors `Analyst` but:
- Uses `TestVisionPrompt`
- Terminates when AI returns `Pass` or `Fail` (or `maxSteps` reached → implicit `Fail`)
- Returns `TestResult`

### `CachingAIClient`

Decorator over any `AIClient`:
- Cache key: `SHA256(screenshotBytes + userPromptText)`
- Cache store: `~/.testpilot/cache/<key>.json`
- On hit: return cached response, emit `(cached)` annotation
- On miss: call underlying client, persist response

### `TestAnalystIOS`

Mirrors `AnalystIOS`:
- Wraps `TestAnalyst` with `CachingAIClient`
- Emits log markers to stdout:
  - `TESTPILOT_STEP: <message>` — one per step
  - `TESTPILOT_STEP: (cached) <message>` — when response came from cache
  - `TESTPILOT_RESULT: PASS <reason>` or `TESTPILOT_RESULT: FAIL <reason>`
- No HTML report generation

---

## CLI Layer

New subcommand `test` alongside existing `analyze`:

```bash
./testpilot test \
  --platform ios \
  --app MyApp \
  --objective "Check if the Buy button is enabled on the product page" \
  [--device <UDID>] [--team-id <TEAM_ID>] \
  [--provider anthropic|openai|gemini] \
  [--api-key <key>] \
  [--max-steps <n>] \
  [--lang en|pt-BR]
```

Changes vs `analyze`:
- No `--output` flag (no HTML report)
- Generated Swift harness uses `TestAnalystIOS` instead of `AnalystIOS`
- Log parsing watches for `TESTPILOT_STEP:` → print in real-time
- Log parsing watches for `TESTPILOT_RESULT:` → determine exit code
- Exit `0` on PASS, exit `1` on FAIL

Terminal output:

```
Running test...
  ✓ Opened the home screen
  ✓ Found product page
  ✗ "Buy" button was disabled

FAILED: "Buy" button was disabled
```

Cache directory `~/.testpilot/cache/` is created automatically on first run.

---

## macOS App Layer

Extends the existing run panel without adding new screens:

- **Segmented control** `Analyze | Test` at the top of the configuration area
  - Maps to `analyze` / `test` subcommand
  - Stored in run model as `mode: RunMode`
- **Mode: Analyze** — identical to current behavior
- **Mode: Test**
  - "Objective" field placeholder changes to *"Check if the Buy button is enabled on the product page"*
  - Log shows each `TESTPILOT_STEP:` prefixed with `✓` or `✗` as it arrives
  - On `TESTPILOT_RESULT:`: banner displayed at top of log
    - Green: **PASSED** — `<reason>`
    - Red: **FAILED** — `<reason>`
  - "Open Report" button hidden (no HTML generated)
  - Run history shows PASS/FAIL badge alongside the test description

---

## Error Handling

- `maxSteps` reached without verdict → implicit `FAIL: test did not reach a conclusion within N steps`
- Cache read error → log warning, proceed without cache (non-fatal)
- Cache write error → log warning, continue (non-fatal)
- AI error → propagate as test failure with error message as reason

---

## Out of Scope

- Gemini context caching (32k token minimum — system prompt is ~400 tokens)
- OpenAI caching (already automatic server-side — no code needed)
- Android test mode (follow-up; same design applies)
- Test suite files / multiple tests per run
- Retry on flaky verdicts
- `CachingAIClient` on-device cache (iOS/Android): current cache path `~/.testpilot/cache/` is macOS/CLI-only; the SDK invoked via XCTest runs in a sandboxed process. For now, caching only benefits CLI reruns — the same test run from terminal twice will hit the cache. In-process caching within a single run is a separate concern.

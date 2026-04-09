# Web Platform Design

**Date:** 2026-04-09
**Status:** Approved

---

## Overview

TestPilot today supports iOS and Android. This spec adds a third platform, `web`, that drives any URL in a browser using Playwright for JVM. It enables both `./testpilot analyze` and `./testpilot test` against web apps, prototypes (e.g., ProtoPie, Figma), and any URL-addressable interface — using the same AI loop, prompts, and CLI flags already in use for mobile.

---

## Problem

Teams need to analyze and test web apps and interactive prototypes with the same vision-based AI loop they use for mobile. There is no web driver today. Adding one should reuse as much existing code as possible and feel identical from the CLI and macOS app.

---

## Goals

- Add `--platform web --url <URL>` to `analyze` and `test` subcommands
- Add `./testpilot web-login --url <URL>` for session setup
- Reuse `Analyst`, `TestAnalyst`, all prompts, and all AI clients without modification
- `analyze` runs in a headed (visible) browser; `test` runs headless
- Sessions (cookies + localStorage) persisted per hostname in `~/.testpilot/sessions/<hostname>.json`
- macOS app: platform selector with Web option; URL field; "Manage Session" button

---

## Architecture

```
./testpilot analyze --platform web --url https://... (bash)
  └── builds testpilot-web.jar (gradlew jvmJar)
  └── java -jar build/testpilot-web.jar ...
        └── AnalystWeb / TestAnalystWeb (jvmMain)
              ├── AnalystDriverWeb → Playwright JVM → browser → PNG bytes
              ├── Analyst / TestAnalyst          ← reused from commonMain, unchanged
              ├── VisionPrompt / TestVisionPrompt ← reused from commonMain, unchanged
              └── AnthropicChatClient / OpenAIChatClient ← reused, unchanged
```

Two runtimes, same AI loop:

| | `analyze --platform web` | `test --platform web` | `web-login` |
|---|---|---|---|
| Browser | headed (visible) | headless | headed |
| Session | loaded if exists | loaded if exists | saved on exit |
| AI loop | `Analyst` | `TestAnalyst` | none |
| Output | HTML report | PASS/FAIL + steps | session file |
| Exit code | 0 | 0 = PASS, 1 = FAIL | 0 |
| Cache | No | Yes (`~/.testpilot/cache/`) | — |

---

## SDK Layer (jvmMain)

### `AnalystDriverWeb`

Implements `AnalystDriver` using Playwright for JVM.

- Viewport: fixed 1280×800
- `screenshotPng()`: `page.screenshot()` → `ByteArray`
- `tap(x, y)`: `page.mouse.click(x * 1280, y * 800)`
- `scroll(direction)`: `page.mouse.wheel(0.0, if (direction == "down") 400.0 else -400.0)`
- `type(x, y, text)`: tap then `page.keyboard.type(text)`
- Session loading: `browser.newContext(storageState = sessionPath)` if file exists

### `AnalystWeb`

Analyze entrypoint for web:

- Opens Playwright headed browser
- Loads session from `~/.testpilot/sessions/<hostname>.json` if present
- Navigates to URL
- Runs `Analyst(driver, aiClient, config)`
- Prints `TESTPILOT_REPORT_START` / `TESTPILOT_REPORT_END` with inline HTML
- Prints `TESTPILOT_REPORT_PATH=<path>` after saving report

### `TestAnalystWeb`

Test entrypoint for web:

- Opens Playwright headless browser
- Loads session from `~/.testpilot/sessions/<hostname>.json` if present
- Navigates to URL
- Wraps AI client with `CachingAIClientJvm`
- Runs `TestAnalyst(driver, aiClient, config)` with `onStep` callback
- Emits `TESTPILOT_STEP: [message]` and `TESTPILOT_RESULT: PASS/FAIL [reason]`

### `CachingAIClientJvm`

Same contract as `CachingAIClient` (iosMain):

- Cache key: FNV-1a 64-bit over sampled screenshot bytes + prompt text
- Cache store: `~/.testpilot/cache/<key>.json` via `java.io.File`
- On hit: return cached response, fire `onCacheHit` callback
- On miss: call delegate, persist response
- Read/write errors: log warning, continue without cache (non-fatal)

### `Main.kt`

Fat JAR entry point:

- Parses args: `--mode analyze|test|login`, `--url`, `--objective`, `--provider`, `--api-key`, `--max-steps`, `--lang`, `--username`, `--password`
- Dispatches to `AnalystWeb`, `TestAnalystWeb`, or manual session save flow
- Runs inside `runBlocking { }`

---

## Session Persistence

**Storage:** `~/.testpilot/sessions/<hostname>.json` — Playwright `storageState` format (cookies + localStorage).

### Automatic login (credential-based)

If `--username` and `--password` are provided and no session file exists for the hostname, TestPilot runs an automatic login pre-step before the main objective:

1. Open browser (headed for `analyze`, headless for `test`)
2. Navigate to URL
3. Run `Analyst` with a fixed `maxSteps = 5` and the goal: `"Log in with username: <username> and password: <password>"` (separate from the main objective's `maxSteps`)
4. On success, save session to `~/.testpilot/sessions/<hostname>.json`
5. Continue to the main objective with the established session

On subsequent runs with the same hostname, the saved session is loaded and the login pre-step is skipped.

Credentials are passed to the JAR via args and never written to disk.

### Manual login (`web-login`)

For complex auth flows (SSO, OAuth, MFA) where credentials alone are not enough:

1. Open headed Playwright browser, navigate to URL
2. Print: `Browser open. Log in, then press Enter to save session.`
3. Wait for Enter keystroke in terminal
4. Call `browserContext.storageState(path = sessionPath)`
5. Close browser, print: `Session saved to ~/.testpilot/sessions/<hostname>.json`

### Session loading

`AnalystWeb` and `TestAnalystWeb` check if `~/.testpilot/sessions/<hostname>.json` exists before creating the browser context. If missing and no credentials provided, proceed without session (no error).

---

## CLI Layer

### New flags

- `--url <URL>` — replaces `--app` when `--platform web`. Required for all web subcommands.
- `--username <user>` — username for automatic login pre-step (optional)
- `--password <pass>` — password for automatic login pre-step (optional; requires `--username`)

### `analyze --platform web`

```bash
./testpilot analyze \
  --platform web \
  --url https://your-app.com \
  --objective "how easy is it to find the checkout flow" \
  [--username user@example.com --password secret] \
  [--provider anthropic|openai] \
  [--api-key <key>] \
  [--max-steps <n>] \
  [--lang en|pt-BR] \
  [--output ./report.html]
```

### `test --platform web`

```bash
./testpilot test \
  --platform web \
  --url https://your-app.com \
  --objective "Check if the Buy button is enabled on the product page" \
  [--provider anthropic|openai] \
  [--api-key <key>] \
  [--max-steps <n>] \
  [--lang en|pt-BR]
```

### `web-login`

```bash
./testpilot web-login --url https://your-app.com
```

### Build step

The bash script checks if `build/testpilot-web.jar` exists. If not (or if source is newer), runs:

```bash
cd sdk && ./gradlew testpilot:jvmJar
```

Then invokes:

```bash
java -jar sdk/testpilot/build/libs/testpilot-jvm.jar \
  --mode analyze|test|login \
  --url "$URL" \
  --objective "$OBJECTIVE" \
  ...
```

Log parsing is identical to iOS test mode: watch for `TESTPILOT_STEP:` and `TESTPILOT_RESULT:` lines on stdout.

---

## macOS App Layer

### Platform selector

Add `Platform` enum to `RunConfig`:

```swift
enum Platform: String, Codable, CaseIterable, Identifiable {
    case ios
    case android
    case web
    var id: String { rawValue }
}
```

`RunConfig` gains `var platform: Platform = .ios`.

### `RunView` changes

- Segmented control for platform: **iOS | Android | Web** (above or below the Analyze/Test mode control)
- When `web`:
  - App name field replaced by URL field (placeholder: `https://your-app.com`)
  - Username and Password fields shown (optional; filled in → automatic login pre-step)
  - Device and Team ID fields hidden
  - "Manage Session" button shown — runs `web-login` in a headed browser subprocess for complex auth (SSO/OAuth/MFA); shown as secondary option below the credential fields
- When `ios` or `android`: existing UI unchanged

### `RunningView` / `ContentView`

No changes needed — stdout marker parsing already handles both modes; web emits the same markers.

### `HistoryView`

`HistoryRowView` shows platform badge: **IOS** / **ANDROID** / **WEB** alongside **ANALYZE** / **TEST**.

---

## Gradle changes

Add `jvmMain` source set and fat JAR task to `sdk/testpilot/build.gradle.kts`:

```kotlin
kotlin {
    jvm()
    // existing targets...

    sourceSets {
        val jvmMain by getting {
            dependencies {
                implementation("com.microsoft.playwright:playwright:1.44.0")
                implementation("io.ktor:ktor-client-cio-jvm:2.2.4")
            }
        }
    }
}

tasks.register<Jar>("jvmJar") {
    archiveBaseName.set("testpilot-jvm")
    manifest { attributes["Main-Class"] = "co.work.testpilot.MainKt" }
    from(sourceSets.main.get().output)
    dependsOn(configurations.runtimeClasspath)
    from(configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) })
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
}
```

---

## Error Handling

| Situation | Behavior |
|-----------|----------|
| `--url` missing for web platform | CLI error: `--url is required for --platform web` |
| `--password` provided without `--username` | CLI error: `--username is required when --password is set` |
| Automatic login fails (wrong credentials, unexpected form) | `FAIL: Login pre-step did not complete` (test) or CLI error (analyze) |
| URL unreachable | Playwright throws; propagated as `FAIL: Could not load URL` (test) or CLI error (analyze) |
| No session file for hostname | Proceed without session, no error |
| Session file corrupt | Log warning, proceed without session (non-fatal) |
| `maxSteps` reached without verdict | `FAIL: Test did not reach a conclusion within N steps` |
| Cache read/write error | Log warning, continue without cache |
| JVM not found | CLI error: `Java runtime not found. Install JDK 11+.` |

---

## Out of Scope

- Android web mode (Playwright runs on JVM, Android path unchanged)
- Mobile viewport emulation (fixed 1280×800 desktop)
- Per-URL session granularity (keyed by hostname)
- Gemini provider on web (same constraint as Android — Anthropic and OpenAI only for JVM)
- Credential storage in `.env` (credentials are passed as flags only, never written to disk by TestPilot)
- Retry on flaky verdicts

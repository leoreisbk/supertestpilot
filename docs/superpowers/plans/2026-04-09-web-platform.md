# Web Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--platform web --url <URL>` support to `./testpilot analyze` and `./testpilot test`, plus a `./testpilot web-login` subcommand for session setup, and matching macOS app UI.

**Architecture:** Add a `jvmMain` source set to the KMM Gradle project. Implement `AnalystDriverWeb` with Playwright for JVM — this is the only new code needed, since `Analyst`, `TestAnalyst`, all prompts, and all AI clients are reused from `commonMain` without modification. The CLI runs the driver via `./gradlew jvmRun` with environment variables, and the macOS app adds a `web` platform option to the existing run configuration UI.

**Tech Stack:** Kotlin Multiplatform (jvmMain), Playwright for Java 1.44.0, Ktor CIO (JVM), existing `Analyst`/`TestAnalyst`/AI client classes from `commonMain`.

---

## File Map

### New files
| File | Responsibility |
|------|---------------|
| `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/AnalystDriverWeb.kt` | Playwright `AnalystDriver` implementation |
| `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/ai/CachingAIClientJvm.kt` | File-based `AIClient` cache decorator for JVM |
| `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/WebSession.kt` | Session path helpers + interactive web-login flow |
| `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/AnalystWeb.kt` | `analyze` entrypoint: headed browser, optional login, HTML report |
| `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/TestAnalystWeb.kt` | `test` entrypoint: headless browser, optional login, stdout markers |
| `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/Main.kt` | JVM `main()`: reads env vars, dispatches to the three modes |

### Modified files
| File | Change |
|------|--------|
| `sdk/testpilot/build.gradle.kts` | Add `jvm()` target, Playwright dependency, `jvmRun` and `installPlaywrightBrowsers` tasks |
| `testpilot` (bash) | Add `web-login` subcommand, `--url`/`--username`/`--password` flags, `web` platform branch |
| `mac-app/TestPilotApp/Models/RunConfig.swift` | Add `.web` to `Platform` enum; add `url`, `username`, `password` fields; update `isValid` |
| `mac-app/TestPilotApp/Services/AnalysisRunner.swift` | Add `webLoginPending` state, `webLogin()`, `saveSession()`, web args branch |
| `mac-app/TestPilotApp/Views/RunView.swift` | Show URL/credentials fields for web; add "Manage Session" sheet |
| `mac-app/TestPilotApp/Views/HistoryView.swift` | Add `.web` color to platform badge |

---

## Task 1: Gradle — add jvmMain target, Playwright dependency, run tasks

**Files:**
- Modify: `sdk/testpilot/build.gradle.kts`

- [ ] **Step 1: Add `jvm()` target and `jvmMain` source set with Playwright dependency**

Open `sdk/testpilot/build.gradle.kts`. The file currently ends after the `iosMain` source set. Add the `jvm()` call and `jvmMain` source set block, and register the two tasks. The full updated file:

```kotlin
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

plugins {
    id("org.jetbrains.kotlin.multiplatform")
    kotlin("plugin.serialization") version "2.1.20"
    id("com.android.library")
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions {
                jvmTarget = "1.8"
            }
        }
    }

    jvm()

    val xcf = XCFramework("TestPilotShared")
    listOf(
        iosX64(),
        iosArm64(),
        iosSimulatorArm64(),
    ).forEach {
        val main by it.compilations.getting
        main.cinterops.create("xctest") {
            defFile("src/iosMain/xctest_${it.name}.def")
        }
        it.compilations.all {
            kotlinOptions {
                freeCompilerArgs += listOf(
                    "-opt-in=kotlinx.cinterop.ExperimentalForeignApi",
                    "-opt-in=kotlin.experimental.ExperimentalNativeApi",
                )
            }
        }

        it.binaries.framework {
            baseName = "TestPilotShared"
            xcf.add(this)
        }
    }

    sourceSets {
        val ktorVersion = "2.2.4"
        val napierVersion = "2.6.1"

        val commonMain by getting {
            dependencies {
                implementation("com.aallam.openai:openai-client:3.1.1")
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
                implementation("io.ktor:ktor-client-core:$ktorVersion")
                implementation("io.ktor:ktor-client-websockets:$ktorVersion")
                implementation("io.ktor:ktor-client-cio:$ktorVersion")
                implementation("io.github.aakira:napier:$napierVersion")
                implementation(kotlin("test"))
            }
        }
        val androidMain by getting {
            dependencies {
                implementation("io.ktor:ktor-client-okhttp:$ktorVersion")
                implementation("androidx.test.uiautomator:uiautomator:2.2.0")
                implementation("androidx.test:core-ktx:1.5.0")
            }
        }
        val iosX64Main by getting
        val iosArm64Main by getting
        val iosSimulatorArm64Main by getting
        val iosMain by creating {
            dependsOn(commonMain)
            iosX64Main.dependsOn(this)
            iosArm64Main.dependsOn(this)
            iosSimulatorArm64Main.dependsOn(this)
            dependencies {
                implementation("io.ktor:ktor-client-darwin:$ktorVersion")
            }
        }
        val jvmMain by getting {
            dependencies {
                implementation("com.microsoft.playwright:playwright:1.44.0")
            }
        }
    }
}

android {
    namespace = "co.work.testpilot"
    compileSdk = 33
    defaultConfig {
        minSdk = 29
        targetSdk = 33
    }
}

// ── Web runner tasks ──────────────────────────────────────────────────────────

fun jvmClasspath() = kotlin.jvm().compilations["main"].let { c ->
    c.output.allOutputs + c.runtimeDependencyFiles
}

tasks.register<JavaExec>("jvmRun") {
    group = "application"
    description = "Run the web runner with env vars set by the testpilot CLI"
    dependsOn("jvmMainClasses")
    mainClass.set("co.work.testpilot.MainKt")
    classpath = jvmClasspath()
}

tasks.register<JavaExec>("installPlaywrightBrowsers") {
    group = "application"
    description = "Download Playwright Chromium browser (one-time setup)"
    dependsOn("jvmMainClasses")
    mainClass.set("com.microsoft.playwright.CLI")
    classpath = jvmClasspath()
    args = listOf("install", "chromium")
}
```

- [ ] **Step 2: Create the jvmMain source directory**

```bash
mkdir -p sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst
mkdir -p sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/ai
```

- [ ] **Step 3: Verify Gradle syncs without errors**

```bash
cd sdk && ./gradlew testpilot:jvmMainClasses
```

Expected: `BUILD SUCCESSFUL`. If you see `Cannot resolve symbol 'Playwright'`, confirm the `jvmMain` source set was added correctly.

- [ ] **Step 4: Commit**

```bash
git add sdk/testpilot/build.gradle.kts
git commit -m "build(sdk): add jvmMain target with Playwright dependency"
```

---

## Task 2: `AnalystDriverWeb` — Playwright browser driver

**Files:**
- Create: `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/AnalystDriverWeb.kt`

- [ ] **Step 1: Create the file**

```kotlin
package co.work.testpilot.analyst

import com.microsoft.playwright.Page
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AnalystDriverWeb(private val page: Page) : AnalystDriver {

    override suspend fun screenshotPng(): ByteArray = withContext(Dispatchers.IO) {
        page.screenshot()
    }

    override suspend fun tap(x: Double, y: Double) = withContext(Dispatchers.IO) {
        page.mouse().click(x * VIEWPORT_WIDTH, y * VIEWPORT_HEIGHT)
    }

    override suspend fun scroll(direction: String) = withContext(Dispatchers.IO) {
        val delta = if (direction == "down") 400.0 else -400.0
        page.mouse().wheel(0.0, delta)
    }

    override suspend fun type(x: Double, y: Double, text: String) = withContext(Dispatchers.IO) {
        page.mouse().click(x * VIEWPORT_WIDTH, y * VIEWPORT_HEIGHT)
        page.keyboard().type(text)
    }

    companion object {
        const val VIEWPORT_WIDTH = 1280
        const val VIEWPORT_HEIGHT = 800
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd sdk && ./gradlew testpilot:jvmMainClasses
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

```bash
git add sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/AnalystDriverWeb.kt
git commit -m "feat(web): add AnalystDriverWeb — Playwright implementation of AnalystDriver"
```

---

## Task 3: `CachingAIClientJvm` — file-based AI response cache

**Files:**
- Create: `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/ai/CachingAIClientJvm.kt`

The cache uses the same FNV-1a 64-bit algorithm as `CachingAIClient` in `iosMain`: samples 1 byte every 200 from screenshot bytes, then hashes each char of the prompt text. Cache key = 16-char lowercase hex string. Files stored as `<cacheDir>/<key>.json`.

- [ ] **Step 1: Create the file**

```kotlin
package co.work.testpilot.ai

import java.io.File

class CachingAIClientJvm(
    private val delegate: AIClient,
    private val cacheDir: String,
    private val onCacheHit: (() -> Unit)? = null,
) : AIClient {

    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        maxTokens: Int,
        temperature: Double,
        imageBytes: ByteArray?,
    ): String {
        val key = cacheKey(imageBytes, messages.lastOrNull()?.content ?: "")
        val cacheFile = File("$cacheDir/$key.json")

        if (cacheFile.exists()) {
            try {
                val cached = cacheFile.readText()
                onCacheHit?.invoke()
                return cached
            } catch (e: Exception) {
                System.err.println("TestPilot: cache read error: ${e.message}")
            }
        }

        val response = delegate.chatCompletion(messages, maxTokens, temperature, imageBytes)

        try {
            File(cacheDir).mkdirs()
            cacheFile.writeText(response)
        } catch (e: Exception) {
            System.err.println("TestPilot: cache write error: ${e.message}")
        }

        return response
    }

    private fun cacheKey(imageBytes: ByteArray?, prompt: String): String {
        // FNV-1a 64-bit — same algorithm as CachingAIClient in iosMain
        var hash = -3750763034362895579L
        val prime = 1099511628211L

        imageBytes?.let { bytes ->
            var i = 0
            while (i < bytes.size) {
                hash = hash xor bytes[i].toLong()
                hash *= prime
                i += 200
            }
        }
        for (char in prompt) {
            hash = hash xor char.code.toLong()
            hash *= prime
        }

        return hash.toULong().toString(16).padStart(16, '0')
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd sdk && ./gradlew testpilot:jvmMainClasses
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

```bash
git add sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/ai/CachingAIClientJvm.kt
git commit -m "feat(web): add CachingAIClientJvm — FNV-1a file cache for JVM"
```

---

## Task 4: `WebSession` — session path helper + interactive login

**Files:**
- Create: `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/WebSession.kt`

`WebSession` owns three responsibilities:
1. `sessionPath(url)` — returns `~/.testpilot/sessions/<hostname>.json`
2. `loadContext(browser, url)` — creates a Playwright `BrowserContext`, loading the stored session if found
3. `saveSession(context, url)` — writes `storageState` to the session file
4. `interactiveLogin(url)` — opens a headed browser, emits `TESTPILOT_LOGIN_READY`, blocks on stdin, saves session on `\n`, emits `TESTPILOT_LOGIN_DONE:<path>`

- [ ] **Step 1: Create the file**

```kotlin
package co.work.testpilot.analyst

import com.microsoft.playwright.Browser
import com.microsoft.playwright.BrowserContext
import com.microsoft.playwright.BrowserType
import com.microsoft.playwright.Playwright
import java.io.File
import java.net.URL
import java.nio.file.Path

object WebSession {

    fun sessionPath(url: String): String {
        val hostname = URL(url).host
        val home = System.getProperty("user.home")
        return "$home/.testpilot/sessions/$hostname.json"
    }

    /** Creates a context with the saved session loaded (if present), at 1280×800. */
    fun loadContext(browser: Browser, url: String): BrowserContext {
        val path = sessionPath(url)
        val opts = Browser.NewContextOptions().setViewportSize(
            AnalystDriverWeb.VIEWPORT_WIDTH, AnalystDriverWeb.VIEWPORT_HEIGHT
        )
        return if (File(path).exists()) {
            browser.newContext(opts.setStorageStatePath(Path.of(path)))
        } else {
            browser.newContext(opts)
        }
    }

    /** Persists the current context's cookies + localStorage to the session file. */
    fun saveSession(context: BrowserContext, url: String) {
        val path = sessionPath(url)
        File(path).parentFile?.mkdirs()
        context.storageState(BrowserContext.StorageStateOptions().setPath(Path.of(path)))
    }

    /**
     * Opens a headed browser for manual login.
     * Emits TESTPILOT_LOGIN_READY to stdout once the page loads.
     * Blocks until a newline arrives on stdin (CLI: Enter; macOS app: writes "\n").
     * Saves session and emits TESTPILOT_LOGIN_DONE:<path>.
     */
    fun interactiveLogin(url: String) {
        val playwright = Playwright.create()
        val browser = playwright.chromium().launch(BrowserType.LaunchOptions().setHeadless(false))
        val context = browser.newContext(
            Browser.NewContextOptions().setViewportSize(
                AnalystDriverWeb.VIEWPORT_WIDTH, AnalystDriverWeb.VIEWPORT_HEIGHT
            )
        )
        val page = context.newPage()
        page.navigate(url)

        println("TESTPILOT_LOGIN_READY")
        System.out.flush()
        readLine() // blocks until '\n'

        val path = sessionPath(url)
        saveSession(context, url)

        browser.close()
        playwright.close()

        println("TESTPILOT_LOGIN_DONE:$path")
        System.out.flush()
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd sdk && ./gradlew testpilot:jvmMainClasses
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

```bash
git add sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/WebSession.kt
git commit -m "feat(web): add WebSession — session path helper and interactive login flow"
```

---

## Task 5: `AnalystWeb` — analyze entrypoint

**Files:**
- Create: `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/AnalystWeb.kt`

Mirrors `AnalystIOS`. Opens a **headed** Playwright browser (so the user can watch the AI navigate). If `username` + `password` are provided and no session file exists for the hostname, runs an auto-login pre-step using `Analyst` with `maxSteps = 5` before the main analysis. Emits `TESTPILOT_REPORT_PATH=<path>` for the CLI.

Note: `buildAIClient()` is a private helper that mirrors the provider switch in `AnalystIOS.kt`. Gemini is not supported on JVM (throws `IllegalArgumentException`).

- [ ] **Step 1: Create the file**

```kotlin
package co.work.testpilot.analyst

import co.work.testpilot.ai.AnthropicChatClient
import co.work.testpilot.ai.OpenAIChatClient
import co.work.testpilot.runtime.AIProvider
import co.work.testpilot.runtime.AIProviderDefaults
import co.work.testpilot.runtime.Config
import co.work.testpilot.runtime.ConfigBuilder
import com.aallam.openai.api.logging.LogLevel
import com.aallam.openai.client.OpenAI
import com.aallam.openai.client.OpenAIConfig
import com.aallam.openai.client.OpenAIHost
import com.microsoft.playwright.BrowserType
import com.microsoft.playwright.Playwright
import io.ktor.client.*
import io.ktor.client.engine.cio.*
import java.io.File

class AnalystWeb(private val config: Config) {

    suspend fun run(
        url: String,
        objective: String,
        outputPath: String,
        username: String? = null,
        password: String? = null,
    ): String {
        val playwright = Playwright.create()
        val browser = playwright.chromium().launch(BrowserType.LaunchOptions().setHeadless(false))
        val httpClient = HttpClient(CIO)

        try {
            val sessionExists = File(WebSession.sessionPath(url)).exists()

            // Auto-login pre-step: runs Analyst with maxSteps=5 to fill in credentials
            if (username != null && password != null && !sessionExists) {
                val loginContext = browser.newContext(
                    com.microsoft.playwright.Browser.NewContextOptions()
                        .setViewportSize(AnalystDriverWeb.VIEWPORT_WIDTH, AnalystDriverWeb.VIEWPORT_HEIGHT)
                )
                val loginPage = loginContext.newPage()
                loginPage.navigate(url)

                val loginConfig = ConfigBuilder()
                    .provider(config.provider)
                    .apiKey(config.apiKey)
                    .maxSteps(5)
                    .language(config.language)
                    .build()
                Analyst(AnalystDriverWeb(loginPage), buildAIClient(loginConfig, httpClient), loginConfig)
                    .run("Log in with username: $username and password: $password")
                WebSession.saveSession(loginContext, url)
                loginContext.close()
            }

            val context = WebSession.loadContext(browser, url)
            val page = context.newPage()
            page.navigate(url)

            val report = Analyst(AnalystDriverWeb(page), buildAIClient(config, httpClient), config)
                .run(objective)
            val html = HtmlReportWriter.generate(report, config.language)

            val file = File(outputPath).also { it.parentFile?.mkdirs() }
            file.writeText(html)
            println("TESTPILOT_REPORT_PATH=${file.absolutePath}")
            return file.absolutePath
        } finally {
            browser.close()
            playwright.close()
            httpClient.close()
        }
    }

    private fun buildAIClient(cfg: Config, httpClient: HttpClient) = when (cfg.provider) {
        AIProvider.Anthropic -> AnthropicChatClient(
            apiKey = cfg.apiKey,
            modelId = cfg.modelId ?: AIProviderDefaults.anthropicModel,
            httpClient = httpClient,
            apiHost = cfg.apiHost ?: "https://api.anthropic.com",
            extraHeaders = cfg.apiHeaders,
        )
        AIProvider.OpenAI -> OpenAIChatClient(
            openAI = OpenAI(config = OpenAIConfig(
                token = cfg.apiKey,
                organization = cfg.apiOrg,
                headers = cfg.apiHeaders,
                host = cfg.apiHost?.let { OpenAIHost(it) } ?: OpenAIHost.OpenAI,
                logLevel = LogLevel.None,
            )),
            modelId = cfg.modelId ?: AIProviderDefaults.openAIModel,
            httpClient = httpClient,
            apiKey = cfg.apiKey,
            apiHost = cfg.apiHost ?: "https://api.openai.com",
        )
        AIProvider.Gemini ->
            throw IllegalArgumentException("Gemini is not supported on web platform. Use anthropic or openai.")
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd sdk && ./gradlew testpilot:jvmMainClasses
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

```bash
git add sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/AnalystWeb.kt
git commit -m "feat(web): add AnalystWeb — analyze entrypoint with headed browser and auto-login"
```

---

## Task 6: `TestAnalystWeb` — test entrypoint

**Files:**
- Create: `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/TestAnalystWeb.kt`

Mirrors `TestAnalystIOS`. Runs **headless** for the test itself. If auto-login is needed, it opens a **headed** browser just for the login pre-step, saves the session, closes that browser, then opens a headless browser for the actual test. Wraps the AI client with `CachingAIClientJvm`. Emits `TESTPILOT_STEP:` and `TESTPILOT_RESULT:` to stdout.

- [ ] **Step 1: Create the file**

```kotlin
package co.work.testpilot.analyst

import co.work.testpilot.ai.AnthropicChatClient
import co.work.testpilot.ai.CachingAIClientJvm
import co.work.testpilot.ai.OpenAIChatClient
import co.work.testpilot.runtime.AIProvider
import co.work.testpilot.runtime.AIProviderDefaults
import co.work.testpilot.runtime.Config
import co.work.testpilot.runtime.ConfigBuilder
import com.aallam.openai.api.logging.LogLevel
import com.aallam.openai.client.OpenAI
import com.aallam.openai.client.OpenAIConfig
import com.aallam.openai.client.OpenAIHost
import com.microsoft.playwright.BrowserType
import com.microsoft.playwright.Playwright
import io.ktor.client.*
import io.ktor.client.engine.cio.*
import java.io.File

class TestAnalystWeb(private val config: Config) {

    suspend fun run(
        url: String,
        objective: String,
        username: String? = null,
        password: String? = null,
    ): TestResult {
        val playwright = Playwright.create()
        val httpClient = HttpClient(CIO)

        try {
            val sessionExists = File(WebSession.sessionPath(url)).exists()

            // Auto-login: use a headed browser so the login form is visible
            if (username != null && password != null && !sessionExists) {
                val loginBrowser = playwright.chromium()
                    .launch(BrowserType.LaunchOptions().setHeadless(false))
                val loginContext = loginBrowser.newContext(
                    com.microsoft.playwright.Browser.NewContextOptions()
                        .setViewportSize(AnalystDriverWeb.VIEWPORT_WIDTH, AnalystDriverWeb.VIEWPORT_HEIGHT)
                )
                val loginPage = loginContext.newPage()
                loginPage.navigate(url)

                val loginConfig = ConfigBuilder()
                    .provider(config.provider)
                    .apiKey(config.apiKey)
                    .maxSteps(5)
                    .language(config.language)
                    .build()
                Analyst(AnalystDriverWeb(loginPage), buildAIClient(loginConfig, httpClient), loginConfig)
                    .run("Log in with username: $username and password: $password")
                WebSession.saveSession(loginContext, url)
                loginBrowser.close()
            }

            // Test run: headless
            val browser = playwright.chromium().launch(BrowserType.LaunchOptions().setHeadless(true))
            val context = WebSession.loadContext(browser, url)
            val page = context.newPage()
            page.navigate(url)

            val cacheDir = "${System.getProperty("user.home")}/.testpilot/cache"
            var lastResponseCached = false
            val aiClient = CachingAIClientJvm(
                delegate = buildAIClient(config, httpClient),
                cacheDir = cacheDir,
                onCacheHit = { lastResponseCached = true },
            )

            val result = TestAnalyst(AnalystDriverWeb(page), aiClient, config).run(objective) { message ->
                val prefix = if (lastResponseCached) "(cached) " else ""
                println("TESTPILOT_STEP: $prefix$message")
                System.out.flush()
                lastResponseCached = false
            }

            val verdict = if (result.passed) "PASS" else "FAIL"
            println("TESTPILOT_RESULT: $verdict ${result.reason}")
            System.out.flush()

            browser.close()
            return result
        } finally {
            playwright.close()
            httpClient.close()
        }
    }

    private fun buildAIClient(cfg: Config, httpClient: HttpClient) = when (cfg.provider) {
        AIProvider.Anthropic -> AnthropicChatClient(
            apiKey = cfg.apiKey,
            modelId = cfg.modelId ?: AIProviderDefaults.anthropicModel,
            httpClient = httpClient,
            apiHost = cfg.apiHost ?: "https://api.anthropic.com",
            extraHeaders = cfg.apiHeaders,
        )
        AIProvider.OpenAI -> OpenAIChatClient(
            openAI = OpenAI(config = OpenAIConfig(
                token = cfg.apiKey,
                organization = cfg.apiOrg,
                headers = cfg.apiHeaders,
                host = cfg.apiHost?.let { OpenAIHost(it) } ?: OpenAIHost.OpenAI,
                logLevel = LogLevel.None,
            )),
            modelId = cfg.modelId ?: AIProviderDefaults.openAIModel,
            httpClient = httpClient,
            apiKey = cfg.apiKey,
            apiHost = cfg.apiHost ?: "https://api.openai.com",
        )
        AIProvider.Gemini ->
            throw IllegalArgumentException("Gemini is not supported on web platform. Use anthropic or openai.")
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd sdk && ./gradlew testpilot:jvmMainClasses
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Commit**

```bash
git add sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/analyst/TestAnalystWeb.kt
git commit -m "feat(web): add TestAnalystWeb — test entrypoint with headless browser, caching, stdout markers"
```

---

## Task 7: `Main.kt` — JVM entry point

**Files:**
- Create: `sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/Main.kt`

Reads configuration from environment variables (set by the CLI before calling `./gradlew jvmRun`). Dispatches to `AnalystWeb`, `TestAnalystWeb`, or `WebSession.interactiveLogin`.

Environment variables consumed:

| Variable | Used by |
|----------|---------|
| `TESTPILOT_MODE` | all (`analyze`, `test`, `login`) |
| `TESTPILOT_WEB_URL` | all |
| `TESTPILOT_API_KEY` | analyze, test |
| `TESTPILOT_PROVIDER` | analyze, test (default: `anthropic`) |
| `TESTPILOT_MAX_STEPS` | analyze, test (default: `20`) |
| `TESTPILOT_LANG` | analyze, test (default: `en`) |
| `TESTPILOT_OUTPUT` | analyze (default: `./report.html`) |
| `TESTPILOT_OBJECTIVE` | analyze, test |
| `TESTPILOT_WEB_USERNAME` | analyze, test (optional) |
| `TESTPILOT_WEB_PASSWORD` | analyze, test (optional) |

- [ ] **Step 1: Create the file**

```kotlin
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
```

- [ ] **Step 2: Verify full build**

```bash
cd sdk && ./gradlew testpilot:jvmMainClasses
```

Expected: `BUILD SUCCESSFUL` with no errors.

- [ ] **Step 3: Verify the jvmRun task exists**

```bash
cd sdk && ./gradlew testpilot:tasks --group application
```

Expected: output includes `jvmRun` and `installPlaywrightBrowsers`.

- [ ] **Step 4: Commit**

```bash
git add sdk/testpilot/src/jvmMain/kotlin/co/work/testpilot/Main.kt
git commit -m "feat(web): add Main.kt — JVM entry point dispatching analyze/test/login via env vars"
```

---

## Task 8: CLI — `web-login` subcommand + `web` platform branch

**Files:**
- Modify: `testpilot` (the bash script at the repo root)

The script currently accepts `analyze` and `test` commands. This task adds:
1. `web-login` as a valid third command
2. `--url`, `--username`, `--password` flags parsed in the main flag loop
3. Platform-aware validation (web needs `--url`, not `--app`)
4. A `web` branch in the platform dispatch section
5. A `web-login` early-exit block after flag parsing

- [ ] **Step 1: Add `URL`, `USERNAME`, `PASSWORD` variables and update the command check**

Find line 4–27 (variables + command check). Replace:

```bash
PLATFORM=""
APP_NAME=""
OBJECTIVE=""
API_KEY="${TESTPILOT_API_KEY:-}"
PROVIDER="${TESTPILOT_PROVIDER:-anthropic}"
MAX_STEPS=20
OUTPUT="./report.html"
LANG_CODE="en"
DEVICE_UDID=""   # physical device UDID (optional; uses booted simulator if omitted)
TEAM_ID=""       # Apple Developer Team ID (required for physical device)

COMMAND="${1:-}"
if [[ "$COMMAND" != "analyze" && "$COMMAND" != "test" ]]; then
  echo "Usage: ./testpilot analyze --platform ios|android --app <name> --objective <text>"
  echo "       [--device <UDID>] [--team-id <TEAM_ID>] [--provider anthropic|openai|gemini]"
  echo "       [--api-key <key>] [--max-steps <n>] [--output <path>] [--lang en|pt-BR]"
  echo ""
  echo "       ./testpilot test --platform ios|android --app <name> --objective <text>"
  echo "       [--device <UDID>] [--team-id <TEAM_ID>] [--provider anthropic|openai|gemini]"
  echo "       [--api-key <key>] [--max-steps <n>] [--lang en|pt-BR]"
  exit 1
fi
TEST_MODE=false
[[ "$COMMAND" == "test" ]] && TEST_MODE=true
shift
```

With:

```bash
PLATFORM=""
APP_NAME=""
URL=""
USERNAME=""
PASSWORD=""
OBJECTIVE=""
API_KEY="${TESTPILOT_API_KEY:-}"
PROVIDER="${TESTPILOT_PROVIDER:-anthropic}"
MAX_STEPS=20
OUTPUT="./report.html"
LANG_CODE="en"
DEVICE_UDID=""   # physical device UDID (optional; uses booted simulator if omitted)
TEAM_ID=""       # Apple Developer Team ID (required for physical device)

COMMAND="${1:-}"
if [[ "$COMMAND" != "analyze" && "$COMMAND" != "test" && "$COMMAND" != "web-login" ]]; then
  echo "Usage: ./testpilot analyze --platform ios|android --app <name> --objective <text>"
  echo "       [--device <UDID>] [--team-id <TEAM_ID>] [--provider anthropic|openai|gemini]"
  echo "       [--api-key <key>] [--max-steps <n>] [--output <path>] [--lang en|pt-BR]"
  echo ""
  echo "       ./testpilot analyze --platform web --url <URL> --objective <text>"
  echo "       ./testpilot test    --platform web --url <URL> --objective <text>"
  echo "       [--username <user>] [--password <pass>]"
  echo "       [--provider anthropic|openai] [--api-key <key>] [--max-steps <n>] [--lang en|pt-BR]"
  echo ""
  echo "       ./testpilot web-login --url <URL>"
  exit 1
fi
TEST_MODE=false
[[ "$COMMAND" == "test" ]] && TEST_MODE=true
shift
```

- [ ] **Step 2: Add `--url`, `--username`, `--password` to the flag-parsing loop**

Find the `while [[ $# -gt 0 ]]; do` block. Add three new cases inside it:

```bash
    --url)       URL="$2";        shift 2 ;;
    --username)  USERNAME="$2";   shift 2 ;;
    --password)  PASSWORD="$2";   shift 2 ;;
```

The full updated loop:

```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)  PLATFORM="$2";     shift 2 ;;
    --app)       APP_NAME="$2";     shift 2 ;;
    --url)       URL="$2";          shift 2 ;;
    --username)  USERNAME="$2";     shift 2 ;;
    --password)  PASSWORD="$2";     shift 2 ;;
    --objective) OBJECTIVE="$2";    shift 2 ;;
    --api-key)   API_KEY="$2";      shift 2 ;;
    --provider)  PROVIDER="$2";     shift 2 ;;
    --max-steps) MAX_STEPS="$2";    shift 2 ;;
    --output)    OUTPUT="$2";       shift 2 ;;
    --lang)      LANG_CODE="$2";    shift 2 ;;
    --device)    DEVICE_UDID="$2";  shift 2 ;;
    --team-id)   TEAM_ID="$2";      shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done
```

- [ ] **Step 3: Add the `web-login` early-exit block**

After the `.env` loading block and before the existing validation block (the lines with `[[ -z "$PLATFORM" ]]`), insert:

```bash
# ── web-login: establish browser session without running a test ──────────────
if [[ "$COMMAND" == "web-login" ]]; then
  [[ -z "$URL" ]] && { echo "Error: --url required for web-login"; exit 1; }
  command -v java >/dev/null 2>&1 || { echo "Error: java not found — install JDK 11+"; exit 1; }

  echo "Building web runner..."
  (cd "$SCRIPT_DIR/sdk" && ./gradlew -q testpilot:jvmMainClasses) \
    || { echo "Error: JVM build failed."; exit 1; }

  TESTPILOT_MODE="login" \
  TESTPILOT_WEB_URL="$URL" \
  TESTPILOT_API_KEY="${API_KEY:-dummy}" \
    (cd "$SCRIPT_DIR/sdk" && ./gradlew -q testpilot:jvmRun)
  exit $?
fi
```

- [ ] **Step 4: Update the existing validation block**

Replace the current validation lines:

```bash
[[ -z "$PLATFORM" ]]  && { echo "Error: --platform required (ios or android)"; exit 1; }
[[ -z "$APP_NAME" ]]  && { echo "Error: --app required"; exit 1; }
[[ -z "$OBJECTIVE" ]] && { echo "Error: --objective required"; exit 1; }
[[ -z "$API_KEY" ]]   && { echo "Error: API key required (--api-key or TESTPILOT_API_KEY in .env)"; exit 1; }
```

With:

```bash
[[ -z "$PLATFORM" ]]  && { echo "Error: --platform required (ios, android, or web)"; exit 1; }
[[ -z "$OBJECTIVE" ]] && { echo "Error: --objective required"; exit 1; }
[[ -z "$API_KEY" ]]   && { echo "Error: API key required (--api-key or TESTPILOT_API_KEY in .env)"; exit 1; }

if [[ "$PLATFORM" == "web" ]]; then
  [[ -z "$URL" ]] && { echo "Error: --url required for --platform web"; exit 1; }
else
  [[ -z "$APP_NAME" ]] && { echo "Error: --app required for --platform $PLATFORM"; exit 1; }
fi
```

- [ ] **Step 5: Add the `web` platform branch**

Find the final `else` block near the end of the script:

```bash
else
  echo "Error: Unknown platform \"$PLATFORM\". Use ios or android."
  exit 1
fi
```

Replace it with:

```bash
elif [[ "$PLATFORM" == "web" ]]; then
  command -v java >/dev/null 2>&1 || { echo "Error: java not found — install JDK 11+"; exit 1; }

  echo "Building web runner..."
  (cd "$SCRIPT_DIR/sdk" && ./gradlew -q testpilot:jvmMainClasses) \
    || { echo "Error: JVM build failed."; exit 1; }

  # Install Playwright browsers on first run
  if [[ ! -d "$HOME/.cache/ms-playwright" ]]; then
    echo "Installing Playwright browsers (first time only)..."
    (cd "$SCRIPT_DIR/sdk" && ./gradlew -q testpilot:installPlaywrightBrowsers) \
      || { echo "Error: Could not install Playwright browsers."; exit 1; }
  fi

  WEB_LOG=$(mktemp)

  TESTPILOT_MODE="$COMMAND" \
  TESTPILOT_WEB_URL="$URL" \
  TESTPILOT_OBJECTIVE="$OBJECTIVE" \
  TESTPILOT_API_KEY="$API_KEY" \
  TESTPILOT_PROVIDER="$PROVIDER" \
  TESTPILOT_MAX_STEPS="$MAX_STEPS" \
  TESTPILOT_LANG="$LANG_CODE" \
  TESTPILOT_OUTPUT="$OUTPUT" \
  TESTPILOT_WEB_USERNAME="$USERNAME" \
  TESTPILOT_WEB_PASSWORD="$PASSWORD" \
    (cd "$SCRIPT_DIR/sdk" && ./gradlew -q testpilot:jvmRun 2>&1) | tee "$WEB_LOG" || true

  if [[ "$TEST_MODE" == "true" ]]; then
    RESULT_LINE=$(grep "^TESTPILOT_RESULT:" "$WEB_LOG" | tail -1)
    rm -f "$WEB_LOG"
    if [[ "$RESULT_LINE" == "TESTPILOT_RESULT: PASS"* ]]; then
      exit 0
    else
      exit 1
    fi
  else
    rm -f "$WEB_LOG"
    echo "Report written to: $OUTPUT"
    open "$OUTPUT" 2>/dev/null || echo "Open $OUTPUT in your browser."
  fi

else
  echo "Error: Unknown platform \"$PLATFORM\". Use ios, android, or web."
  exit 1
fi
```

- [ ] **Step 6: Verify the script parses correctly**

```bash
bash -n testpilot
```

Expected: no output (no syntax errors).

- [ ] **Step 7: Smoke test web-login help**

```bash
./testpilot web-login 2>&1 | head -5
```

Expected: `Error: --url required for web-login`

- [ ] **Step 8: Commit**

```bash
git add testpilot
git commit -m "feat(cli): add web platform — web-login subcommand, --url/--username/--password flags, web branch"
```

---

## Task 9: macOS — `Platform.web` + `RunConfig` web fields

**Files:**
- Modify: `mac-app/TestPilotApp/Models/RunConfig.swift`

The `Platform` enum already exists with `.ios` and `.android`. Add `.web` and update `displayName` and `isValid`.

- [ ] **Step 1: Add `.web` to `Platform` and update `displayName`**

Find:

```swift
enum Platform: String, Codable, CaseIterable, Identifiable {
    case ios = "ios"
    case android = "android"
    var id: String { rawValue }
    var displayName: String { self == .ios ? "iOS" : "Android" }
}
```

Replace with:

```swift
enum Platform: String, Codable, CaseIterable, Identifiable {
    case ios = "ios"
    case android = "android"
    case web = "web"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ios:     return "iOS"
        case .android: return "Android"
        case .web:     return "Web"
        }
    }
}
```

- [ ] **Step 2: Add `url`, `username`, `password` fields to `RunConfig` and update `isValid`**

Find:

```swift
@Observable
final class RunConfig {
    var platform: Platform = .ios
    var selectedDevice: DeviceInfo? = nil
    var appName: String = ""
    var objective: String = ""
    var language: Language = .en
    var maxSteps: Int = 20
    // Note: tilde is expanded by AnalysisRunner via NSString.expandingTildeInPath
    var outputPath: String = "~/Desktop/report.html"
    var providerOverride: AIProvider? = nil
    var parameters: [RunParameter] = []
    var mode: RunMode = .analyze

    var isValid: Bool {
        selectedDevice != nil
            && !appName.trimmingCharacters(in: .whitespaces).isEmpty
            && !objective.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
```

Replace with:

```swift
@Observable
final class RunConfig {
    var platform: Platform = .ios
    var selectedDevice: DeviceInfo? = nil
    var appName: String = ""
    var url: String = ""
    var username: String = ""
    var password: String = ""
    var objective: String = ""
    var language: Language = .en
    var maxSteps: Int = 20
    // Note: tilde is expanded by AnalysisRunner via NSString.expandingTildeInPath
    var outputPath: String = "~/Desktop/report.html"
    var providerOverride: AIProvider? = nil
    var parameters: [RunParameter] = []
    var mode: RunMode = .analyze

    var isValid: Bool {
        guard !objective.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if platform == .web {
            return !url.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return selectedDevice != nil
            && !appName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
```

- [ ] **Step 3: Build the macOS app to verify no compile errors**

```bash
cd mac-app && xcodebuild build -scheme TestPilotApp -destination 'platform=macOS' 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add mac-app/TestPilotApp/Models/RunConfig.swift
git commit -m "feat(mac): add Platform.web and url/username/password fields to RunConfig"
```

---

## Task 10: macOS — `RunView` web UI

**Files:**
- Modify: `mac-app/TestPilotApp/Views/RunView.swift`

When `config.platform == .web`:
- Hide the device picker
- Replace the "App name" `TextField` with a URL `TextField`
- Show optional username + password fields below the objective editor
- Show a "Manage Session" button that calls `runner.webLogin(config:settings:)`
- When `runner.state == .webLoginPending`, show a sheet with a "Save Session" button

- [ ] **Step 1: Replace the device picker + app name section with a platform-conditional block**

Find:

```swift
                HStack {
                    Picker("Device", selection: $config.selectedDevice) {
                        Text("Select a device").tag(Optional<DeviceInfo>(nil))
                        ForEach(detector.devices) { device in
                            Text(device.displayName).tag(Optional(device))
                        }
                    }
                    if detector.isRefreshing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Button {
                            Task { await detector.refresh(for: config.platform) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh device list")
                    }
                }

                TextField("App name", text: $config.appName)
```

Replace with:

```swift
                if config.platform != .web {
                    HStack {
                        Picker("Device", selection: $config.selectedDevice) {
                            Text("Select a device").tag(Optional<DeviceInfo>(nil))
                            ForEach(detector.devices) { device in
                                Text(device.displayName).tag(Optional(device))
                            }
                        }
                        if detector.isRefreshing {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button {
                                Task { await detector.refresh(for: config.platform) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh device list")
                        }
                    }

                    TextField("App name", text: $config.appName)
                } else {
                    TextField("URL", text: $config.url)
                        .textContentType(.URL)
                }
```

- [ ] **Step 2: Add username/password fields and "Manage Session" button after the objective editor**

Find the closing `}` of the `Section("Required")` block (right after the `TextEditor` block):

```swift
                ZStack(alignment: .topLeading) {
                    ...
                    TextEditor(text: $config.objective)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                }
            }
```

Replace with:

```swift
                ZStack(alignment: .topLeading) {
                    if config.objective.isEmpty {
                        let placeholder = config.mode == .test
                            ? "Check if the Buy button is enabled on the product page…"
                            : "Describe what to analyze…"
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $config.objective)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                }

                if config.platform == .web {
                    TextField("Username (optional)", text: $config.username)
                    SecureField("Password (optional)", text: $config.password)
                    Button("Manage Session…") {
                        runner.webLogin(config: config, settings: settings)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .help("Open a browser to log in manually — useful for SSO or OAuth")
                }
            }
```

- [ ] **Step 3: Add the `.webLoginPending` sheet**

Find the `.navigationTitle(...)` modifier at the bottom of the `body`:

```swift
        .navigationTitle(config.mode == .test ? "New Test" : "New Analysis")
    }
}
```

Replace with:

```swift
        .navigationTitle(config.mode == .test ? "New Test" : "New Analysis")
        .sheet(isPresented: Binding(
            get: { if case .webLoginPending = runner.state { return true } else { return false } },
            set: { if !$0 { runner.cancel() } }
        )) {
            VStack(spacing: 20) {
                Text("Log in to \(config.url)")
                    .font(.headline)
                Text("A browser window has opened. Complete login, then tap Save Session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Save Session") {
                    runner.saveSession()
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel") {
                    runner.cancel()
                }
                .buttonStyle(.bordered)
            }
            .padding(32)
            .frame(minWidth: 320)
        }
    }
}
```

- [ ] **Step 4: Build to verify no compile errors**

```bash
cd mac-app && xcodebuild build -scheme TestPilotApp -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add mac-app/TestPilotApp/Views/RunView.swift
git commit -m "feat(mac): RunView web UI — URL/credentials fields, Manage Session sheet"
```

---

## Task 11: macOS — `AnalysisRunner` web args + `webLogin` + `HistoryView` badge

**Files:**
- Modify: `mac-app/TestPilotApp/Services/AnalysisRunner.swift`
- Modify: `mac-app/TestPilotApp/Views/HistoryView.swift`

### AnalysisRunner changes

Add `.webLoginPending` state, branch the args construction for web, implement `webLogin()` and `saveSession()`.

- [ ] **Step 1: Add `.webLoginPending` to `AnalysisState`**

Find:

```swift
enum AnalysisState: Equatable {
    case idle
    case running(statusLine: String)
    case testRunning(steps: [TestStep])
    case completed(reportPath: String)
    case testPassed(reason: String, steps: [TestStep])
    case testFailed(reason: String, steps: [TestStep])
    case failed(error: String)
}
```

Replace with:

```swift
enum AnalysisState: Equatable {
    case idle
    case running(statusLine: String)
    case testRunning(steps: [TestStep])
    case completed(reportPath: String)
    case testPassed(reason: String, steps: [TestStep])
    case testFailed(reason: String, steps: [TestStep])
    case failed(error: String)
    case webLoginPending
}
```

- [ ] **Step 2: Update `run()` to pass `--url` instead of `--app` for web**

Find in `run()`:

```swift
        var args: [String] = [
            config.mode.rawValue,
            "--platform", config.platform.rawValue,
            "--app",      config.appName,
            "--objective", effectiveObjective,
            "--lang",     config.language.rawValue,
            "--max-steps", "\(config.maxSteps)",
        ]
        if config.mode == .analyze {
            args += ["--output", outputPath]
        }

        if let device = config.selectedDevice, device.isPhysical {
            args += ["--device", device.id]
            if !settings.teamId.isEmpty {
                args += ["--team-id", settings.teamId]
            }
        }
```

Replace with:

```swift
        var args: [String] = [
            config.mode.rawValue,
            "--platform",  config.platform.rawValue,
            "--objective", effectiveObjective,
            "--lang",      config.language.rawValue,
            "--max-steps", "\(config.maxSteps)",
        ]

        if config.platform == .web {
            args += ["--url", config.url]
            if !config.username.isEmpty { args += ["--username", config.username] }
            if !config.password.isEmpty { args += ["--password", config.password] }
        } else {
            args += ["--app", config.appName]
            if let device = config.selectedDevice, device.isPhysical {
                args += ["--device", device.id]
                if !settings.teamId.isEmpty {
                    args += ["--team-id", settings.teamId]
                }
            }
        }

        if config.mode == .analyze {
            args += ["--output", outputPath]
        }
```

- [ ] **Step 3: Add `webLogin()` and `saveSession()` functions**

After the `reset()` function at the bottom of `AnalysisRunner`, add:

```swift
    func webLogin(config: RunConfig, settings: SettingsStore) {
        guard case .idle = state else { return }

        let scriptURL: URL
        if !settings.scriptPath.isEmpty {
            let expanded = NSString(string: settings.scriptPath).expandingTildeInPath
            scriptURL = URL(fileURLWithPath: expanded)
        } else if let bundled = Bundle.main.url(forResource: "testpilot", withExtension: nil) {
            scriptURL = bundled
        } else {
            state = .failed(error: "testpilot script not found — set the script path in Settings")
            return
        }

        var args: [String] = ["web-login", "--url", config.url]
        let provider = config.providerOverride ?? settings.provider
        args += ["--provider", provider.rawValue]

        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin",
                          "/usr/local/bin", "/usr/local/sbin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extraPaths.joined(separator: ":") + ":" + currentPath
        env["TESTPILOT_API_KEY"]  = settings.apiKey
        env["TESTPILOT_PROVIDER"] = provider.rawValue

        let p = Process()
        p.executableURL = scriptURL
        p.arguments = args
        p.environment = env

        let stdin  = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardInput  = stdin
        p.standardOutput = stdout
        p.standardError  = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else { return }
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                DispatchQueue.main.async {
                    guard let self else { return }
                    if trimmed == "TESTPILOT_LOGIN_READY" {
                        self.state = .webLoginPending
                    } else if trimmed.hasPrefix("TESTPILOT_LOGIN_DONE:") {
                        stdout.fileHandleForReading.readabilityHandler = nil
                        self.state = .idle
                    }
                }
            }
        }

        p.terminationHandler = { [weak self] _ in
            stdout.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self else { return }
                if case .webLoginPending = self.state {
                    self.state = .idle
                }
            }
        }

        state = .running(statusLine: "Opening browser for login…")
        process = p

        do {
            try p.run()
        } catch {
            state = .failed(error: error.localizedDescription)
        }
    }

    func saveSession() {
        guard case .webLoginPending = state else { return }
        if let stdin = process?.standardInput as? Pipe {
            stdin.fileHandleForWriting.write(Data([10])) // "\n"
        }
    }
```

- [ ] **Step 4: Add `.web` color to `HistoryRowView`**

In `HistoryView.swift`, find:

```swift
                        .background(record.platform == .ios
                                    ? Color.blue.opacity(0.15)
                                    : Color.green.opacity(0.15))
```

Replace with:

```swift
                        .background({
                            switch record.platform {
                            case .ios:     return Color.blue.opacity(0.15)
                            case .android: return Color.green.opacity(0.15)
                            case .web:     return Color.purple.opacity(0.15)
                            }
                        }())
```

- [ ] **Step 5: Build and run macOS tests**

```bash
cd mac-app && xcodebuild test -scheme TestPilotApp -destination 'platform=macOS' 2>&1 | grep -E "Test Suite|error:|BUILD|passed|failed"
```

Expected: `BUILD SUCCEEDED` and all existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add mac-app/TestPilotApp/Services/AnalysisRunner.swift \
        mac-app/TestPilotApp/Views/HistoryView.swift
git commit -m "feat(mac): AnalysisRunner web args, webLogin/saveSession, HistoryView web badge"
```

---

## Self-Review

After completing all tasks, verify the following against the spec:

- [ ] `./testpilot analyze --platform web --url https://example.com --objective "..." ` runs without error (needs real API key + Java)
- [ ] `./testpilot test --platform web --url https://example.com --objective "..."` exits 0 or 1 based on AI verdict
- [ ] `./testpilot web-login --url https://example.com` opens a browser and emits `TESTPILOT_LOGIN_READY`
- [ ] `--username` + `--password` triggers auto-login pre-step when no session exists
- [ ] Session file appears at `~/.testpilot/sessions/<hostname>.json` after login
- [ ] Second run on same URL loads cached session (no re-login)
- [ ] `~/.testpilot/cache/` populated on test mode runs
- [ ] macOS app: Web appears in platform picker; URL field shown; device picker hidden
- [ ] macOS app: Manage Session button triggers webLogin, sheet appears, Save Session writes to stdin
- [ ] macOS app: History shows purple WEB badge
- [ ] Gemini throws a clear error message on web platform
- [ ] All existing macOS tests pass

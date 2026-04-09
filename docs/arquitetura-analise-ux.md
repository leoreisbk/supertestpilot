# Arquitetura do TestPilot — referência técnica

Este documento descreve o funcionamento interno dos dois modos do TestPilot: `analyze` (análise exploratória) e `test` (teste determinístico com PASS/FAIL), nas três plataformas suportadas: iOS, Android e Web. Destinado a engenheiros que precisam entender, manter ou estender o sistema.

---

## O que foi construído — visão geral da evolução

O TestPilot open-source original era uma biblioteca KMM para engenheiros: recebia instruções em linguagem natural e as executava em apps móveis via XCTest/UIAutomator. Não havia interface visual, não havia modo de análise exploratória, não havia suporte web, e o foco era automação de tarefas definidas.

Esta versão estendeu essa base com uma arquitetura significativamente mais ampla:

| | TestPilot original | Esta versão |
|---|---|---|
| Entrada | Instruções pré-definidas | Objetivo em linguagem natural |
| Percepção | Não se aplica | Screenshot + IA visão a cada step |
| Modo análise | Não existia | `Analyst` + `HtmlReportWriter` |
| Modo teste | Não existia | `TestAnalyst` + `CachingAIClient` |
| Plataformas | iOS, Android | iOS, Android, Web (Playwright/JVM) |
| Interface | CLI only | CLI + app macOS (SwiftUI) |
| Login | Não existia | Auto-login + sessão persistida (web) / pre-step (mobile) |
| Multi-provider | OpenAI only | Anthropic, OpenAI, Gemini |

A lógica central — `Analyst`, `TestAnalyst`, prompts, AI clients — vive em `commonMain` e é compartilhada entre as três plataformas sem duplicação.

---

## Visão geral

O TestPilot é um projeto **Kotlin Multiplatform (KMM)**. A lógica central vive em `commonMain` e é compilada para três runtimes:

- **iOS** — XCFramework consumido via XCTest
- **Android** — AAR rodando via UIAutomator/AndroidJUnit4
- **Web** — fat JAR JVM com Playwright para controle de browser

O ponto de entrada é um script bash que orquestra o build, a injeção de configuração e a execução.

### Modo `analyze` (exploratório)

```
./testpilot analyze (bash)
  ├── [ios/android] build SDK → xcodebuild / adb instrument
  │       └── AnalystIOS / AnalystAndroid (Kotlin)
  │             └── [login pre-step se --username/--password]
  │             └── Analyst.kt (loop compartilhado)
  │                   ├── AnalystDriver (screenshot, tap, scroll, type)
  │                   ├── AIClient (Anthropic / OpenAI / Gemini)
  │                   └── HtmlReportWriter → report.html
  └── [web] build jvmJar → java -jar testpilot-jvm.jar
              └── AnalystWeb (jvmMain)
                    └── [login pre-step se --username/--password]
                    └── Analyst.kt (loop compartilhado, reusado)
                          ├── AnalystDriverWeb → Playwright headed
                          ├── AIClient (Anthropic / OpenAI)
                          └── HtmlReportWriter → report.html
```

### Modo `test` (determinístico)

```
./testpilot test (bash)
  ├── [ios/android] build SDK → xcodebuild / adb instrument
  │       └── TestAnalystIOS / TestAnalystAndroid (Kotlin)
  │             └── [login pre-step se --username/--password]
  │             └── CachingAIClient → cache em NSCachesDirectory / arquivo
  │             └── TestAnalyst.kt (loop determinístico)
  │                   └── TestResult → TESTPILOT_RESULT: PASS/FAIL
  └── [web] build jvmJar → java -jar testpilot-jvm.jar
              └── TestAnalystWeb (jvmMain)
                    └── [login pre-step se --username/--password]
                    └── CachingAIClientJvm → cache em ~/.testpilot/cache/
                    └── TestAnalyst.kt (loop determinístico, reusado)
                          ├── AnalystDriverWeb → Playwright headless
                          └── TestResult → TESTPILOT_RESULT: PASS/FAIL
  └── CLI parseia TESTPILOT_RESULT: → exit 0 (PASS) ou exit 1 (FAIL)
```

| | `analyze` | `test` |
|---|---|---|
| Subcomando | `./testpilot analyze` | `./testpilot test` |
| Classe iOS | `AnalystIOS` | `TestAnalystIOS` |
| Classe Web | `AnalystWeb` | `TestAnalystWeb` |
| Loop | `Analyst` | `TestAnalyst` |
| Prompt | `VisionPrompt` | `TestVisionPrompt` |
| Browser (web) | headed | headless |
| Saída | Relatório HTML | PASS/FAIL + steps |
| Cache de resposta IA | Não | Sim (iOS: `NSCachesDirectory`; JVM: `~/.testpilot/cache/`) |
| Exit code | Sempre 0 | 0 = PASS, 1 = FAIL |

---

## App macOS

O app macOS (`mac-app/`) é uma camada de interface SwiftUI sobre o mesmo CLI. Não há lógica de análise no app — ele apenas spawna o processo `testpilot` e parseia o stdout em tempo real.

```
Usuário (RunView)
  └── AnalysisRunner.run(config, settings)
        └── Process(executableURL: testpilot, arguments: [...])
              ├── stdout → parse TESTPILOT_STEP / TESTPILOT_RESULT / TESTPILOT_REPORT_PATH
              └── stderr → capturado para mensagem de erro em caso de falha
```

**Estado da UI:** `AnalysisState` enum com os casos `idle`, `running`, `testRunning`, `webLoginPending`, `completed`, `testPassed`, `testFailed`, `failed`. O `AnalysisRunner` é um `@Observable` — a view reage diretamente às mudanças de estado.

**Fluxo `web-login`:** `AnalysisRunner.webLogin()` spawna o processo com stdin aberto. Ao receber `TESTPILOT_LOGIN_READY` no stdout, transiciona para `.webLoginPending` e exibe o sheet de login. `saveSession()` escreve `\n` no stdin para sinalizar ao processo que salve e encerre.

**Persistência:** `HistoryStore` serializa `[RunRecord]` em JSON no Application Support. `SettingsStore` persiste API key no Keychain e demais preferências em `UserDefaults`.

---

## Fluxo de execução (iOS)

### 1. CLI — `testpilot` (bash script)

**Detecção de dispositivo/simulador**

- **Físico** (`--device <UDID>`): usa `xcrun devicectl device info apps` para listar apps instalados
- **Simulador** (padrão): usa `xcrun simctl list devices` para encontrar o simulador em execução

O bundle ID é resolvido por correspondência fuzzy no nome do app. Se houver múltiplos matches, exibe seleção interativa.

**Geração do arquivo de teste**

Antes de cada execução, o script sobrescreve `harness/AnalystTests/AnalystTests.swift` com a configuração do run atual (provider, API key, objective, maxSteps, language, bundleId). Isso permite usar o mesmo target XCTest para qualquer análise sem recompilar o host app.

**Invocação do xcodebuild**

```bash
xcodebuild test \
  -project harness/Harness.xcodeproj \
  -scheme AnalystTests \
  -destination "platform=iOS Simulator,id=<UDID>" \
  # Para dispositivo físico:
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<TEAM_ID>
```

A saída é monitorada em busca da linha `TESTPILOT_REPORT_PATH=<path>`, impressa pelo Kotlin ao finalizar o relatório.

**Recuperação do relatório**

- **Simulador**: `cp` direto do `NSTemporaryDirectory()`
- **Físico**: `xcrun devicectl device copy off --device <UDID> --source <path> --destination <output>`

---

### 2. Harness iOS

O iOS não permite que processos externos controlem apps arbitrários ou tirem screenshots. A Apple libera essas permissões exclusivamente dentro do contexto XCTest. O `harness/` existe para criar esse contexto.

**Estrutura:**

```
harness/
  Harness.xcodeproj/
  HarnessApp/
    AppDelegate.swift     ← app host vazio (UIViewController raiz)
  AnalystTests/
    AnalystTests.swift    ← gerado pelo CLI a cada run
```

**HarnessApp** é um UIKit app minimalista — sem lógica, apenas scaffolding para o test runner.

**AnalystTests** é o XCTest que chama `AnalystIOS.run(config)`. O arquivo é sobrescrito pelo bash antes de cada execução para injetar a configuração do run.

---

### 3. XCFramework

O build KMM produz `TestPilotShared.xcframework` com 3 slices:

| Slice | Destino |
|-------|---------|
| `iosX64` | Simulador Intel |
| `iosArm64` | Dispositivo físico |
| `iosSimulatorArm64` | Simulador Apple Silicon |

**Interop com XCTest:**

Os headers do XCTest são expostos ao Kotlin via C interop. Os arquivos `.def` em `sdk/testpilot/src/iosMain/` são gerados por `build_ios_sdk.sh` a partir de templates `.templ` que recebem os caminhos do Xcode SDK. **Nunca edite os `.def` diretamente.**

---

## O loop de análise — `Analyst.kt`

Localização: `sdk/testpilot/src/commonMain/…/analyst/Analyst.kt`

```kotlin
for (i in 0 until config.maxSteps) {
    val screenshot = driver.screenshotPng()

    // Detecção de tela travada
    val fp = fingerprint(screenshot)
    stuckCount = if (fp == lastFingerprint) stuckCount + 1 else 0
    lastFingerprint = fp
    if (stuckCount >= 5) { driver.scroll("up"); stuckCount = 0; continue }

    // Consulta à IA
    val action = VisionPrompt.run(config, aiClient, screenshot, observations, stuckCount)

    // Execução da ação
    when (action) {
        is Tap    → driver.tap(action.x, action.y)
        is Scroll → driver.scroll(action.direction)
        is Type   → driver.type(action.x, action.y, action.text)
        is Done, is Pass, is Fail → break   // Pass/Fail também encerram o loop
    }

    observations += action.observation
}

// Geração do summary
val summary = generateSummary(config, aiClient, observations)
return AnalysisReport(objective, summary, steps, duration)
```

### Detecção de tela travada (stuck detection)

A cada passo, é calculado um **fingerprint leve** do PNG capturado:

```kotlin
private fun fingerprint(png: ByteArray): Int {
    var sum = 0; var i = 0
    while (i < png.size) { sum += png[i].toInt(); i += 200 }
    return sum
}
```

Amostra 1 byte a cada 200 — O(n/200). Detecta mudanças de pixel sem comparação completa.

Se o fingerprint não mudar por **5 steps consecutivos**, o driver executa um scroll forçado para cima e o contador é zerado. A partir de 3 steps travados, o prompt enviado à IA inclui um aviso explícito para que ela considere ações alternativas (ex: voltar, fechar modal).

---

## Suporte multi-provider de IA

### Interface comum

```kotlin
interface AIClient {
    suspend fun chatCompletion(
        messages: List<ChatMessage>,
        maxTokens: Int,
        temperature: Double,
        imageBytes: ByteArray? = null,  // screenshot em PNG
    ): String
}
```

### Implementações

| Provider | Endpoint | Formato da imagem |
|----------|----------|--------------------|
| **Anthropic** | `api.anthropic.com/v1/messages` | Base64 em content block `type=image` |
| **OpenAI** | `api.openai.com/v1/chat/completions` | Base64 em data URI dentro de `image_url` |
| **Gemini** | `generativelanguage.googleapis.com/…:generateContent` | Base64 em `inlineData` com MIME type |

**Nota:** Gemini não está disponível no path Android nem no Web. Apenas Anthropic e OpenAI funcionam nessas plataformas.

**OpenAI tem dois paths:** quando há `imageBytes`, usa HTTP manual via Ktor (o SDK oficial não suporta visão no KMM). Para mensagens sem imagem (ex: geração do summary), usa o SDK oficial `com.aallam.openai`.

### Modelos padrão

```kotlin
object AIProviderDefaults {
    const val openAIModel    = "gpt-4o"
    const val anthropicModel = "claude-sonnet-4-6"
    const val geminiModel    = "gemini-2.5-flash"
}
```

Todos podem ser sobrescritos via `ConfigBuilder.modelId()`.

### ConfigBuilder

```kotlin
ConfigBuilder()
    .provider(AIProvider.Anthropic)
    .apiKey("sk-...")
    .modelId("claude-opus-4-6")           // opcional; usa padrão
    .apiHost("https://proxy.interno")     // opcional; redireciona para proxy
    .apiOrg("org-...")                    // apenas OpenAI
    .apiHeader("X-Custom", "value")       // headers extras
    .maxTokens(1024)
    .temperature(0.0)                     // resposta determinística
    .maxSteps(20)
    .language("pt-BR")
    .build()
```

---

## Prompts

### `VisionPrompt.kt` (modo analyze)

O prompt de sistema instrui a IA a agir como analista de UX explorando um app. O prompt do usuário inclui:

- O objetivo da análise
- As observações dos steps anteriores (contexto acumulado)
- A screenshot atual (base64)
- Aviso de tela travada se `stuckCount >= 1`

A IA deve responder com um JSON estruturado:

```json
{
  "action": "tap" | "scroll" | "type" | "done",
  "x": 0.5,           // coordenada normalizada 0.0–1.0 (tap/type)
  "y": 0.72,
  "direction": "down", // scroll
  "text": "...",       // type
  "observation": "O botão de login está pouco destacado na tela inicial"
}
```

**Resiliência a JSON truncado:** `AnalysisAction.repairTruncatedJson()` fecha JSON incompleto descartando o último campo mal-formado, evitando falhas por respostas cortadas por `maxTokens`.

### `TestVisionPrompt.kt` (modo test)

O prompt de sistema instrui a IA a agir como avaliador determinístico:

- Cada step: descreve o que está visível e decide a próxima ação
- Quando há evidência suficiente: retorna `pass` ou `fail` imediatamente, sem explorar mais
- `temperature = 0.0`

A IA responde no mesmo formato JSON, mas com dois novos valores de `action`:

```json
{
  "action": "tap" | "scroll" | "type" | "pass" | "fail",
  "reason": "O botão Buy está visível e habilitado na tela de produto"
}
```

O campo `reason` é obrigatório em `pass` e `fail`.

---

## O loop determinístico — `TestAnalyst.kt`

Localização: `sdk/testpilot/src/commonMain/…/analyst/TestAnalyst.kt`

Mirrors `Analyst`, mas:
- Usa `TestVisionPrompt` em vez de `VisionPrompt`
- Termina quando a IA retorna `Pass` ou `Fail` (ou `Done`)
- Se `maxSteps` for atingido sem veredicto → `TestResult(passed=false, reason="Test did not reach a conclusion within N steps")`
- Retorna `TestResult(passed, reason, steps)` em vez de `AnalysisReport`

```kotlin
data class TestResult(
    val passed: Boolean,
    val reason: String,
    val steps: List<String>,
)
```

### `AnalysisAction` — extensões para o modo test

```kotlin
sealed class AnalysisAction {
    // ações existentes...
    data class Pass(val reason: String) : AnalysisAction()
    data class Fail(val reason: String) : AnalysisAction()
}
```

---

## Cache de respostas — `CachingAIClient.kt`

Localização: `sdk/testpilot/src/iosMain/…/ai/CachingAIClient.kt`

Decorator sobre qualquer `AIClient`. Ativo apenas no modo `test`.

**Chave de cache:** FNV-1a 64-bit sobre amostra do screenshot (1 byte a cada 200) + texto completo do prompt → nome de arquivo hexadecimal de 16 caracteres.

**Armazenamento:** `NSCachesDirectory/testpilot-cache/<key>.json` — persiste entre execuções separadas do mesmo test target (o container de processo do XCTest é reutilizado).

**Hit:** retorna resposta cacheada; dispara callback `onCacheHit` para que o step seja anotado com `(cached)`.

**Miss:** chama o cliente subjacente e persiste a resposta.

**Erros:** leitura/escrita do cache não são fatais — em caso de erro, o cliente subjacente é chamado normalmente.

---

## Marcadores stdout

Todas as plataformas emitem linhas prefixadas para o stdout durante a execução. O CLI e o app macOS monitoram essas linhas em tempo real:

| Linha | Quando |
|-------|--------|
| `TESTPILOT_STEP: <mensagem>` | Passo executado (modo test) |
| `TESTPILOT_STEP: (cached) <mensagem>` | Passo executado a partir do cache |
| `TESTPILOT_RESULT: PASS <motivo>` | Teste aprovado |
| `TESTPILOT_RESULT: FAIL <motivo>` | Teste reprovado |
| `TESTPILOT_REPORT_PATH=<caminho>` | Caminho do relatório HTML gerado (modo analyze) |
| `TESTPILOT_LOGIN_READY` | Browser aberto aguardando login manual (`web-login`) |
| `TESTPILOT_LOGIN_DONE:<caminho>` | Sessão salva; caminho do arquivo de sessão |

---

## Geração do relatório — `HtmlReportWriter.kt`

O relatório é um **HTML autossuficiente**: screenshots embutidas como data URIs em base64. Não há dependências externas — o arquivo pode ser arquivado ou enviado por e-mail.

**Estrutura do HTML:**

```
<header>   — objetivo + metadados (N steps, duração)
<summary>  — parágrafo gerado pela IA com a avaliação geral
<steps>    — para cada step: screenshot inline + ação + observação
```

**Localização:** labels em inglês (padrão) ou pt-BR, selecionados via `config.language`.

**Tamanho típico:** 5–20 MB dependendo da quantidade de steps e resolução do device.

---

## Login pre-step (todas as plataformas)

Quando `--username` e `--password` são fornecidos, os entrypoints de todas as plataformas executam um passo de login **antes** do objetivo principal:

```kotlin
if (!username.isNullOrEmpty() && !password.isNullOrEmpty()) {
    val loginConfig = config.copy(maxSteps = 5)
    Analyst(driver, aiClient, loginConfig)
        .run("Log in with username: $username and password: $password")
}
```

- Reutiliza o mesmo `Analyst` e `AnalystDriver` — sem código extra por plataforma
- `maxSteps = 5` limita o pre-step independente do `maxSteps` do objetivo principal
- Para o modo `test`, o pre-step usa o `baseClient` (cliente direto, sem cache) para não poluir o cache do teste

**Web — sessão persistida:** após o login, o contexto Playwright é salvo em `~/.testpilot/sessions/<hostname>.json`. Nas execuções seguintes com a mesma URL, o arquivo é carregado e o pre-step é pulado.

**iOS/Android — sem persistência de sessão:** o pre-step é executado em toda execução em que as credenciais são passadas (o estado de login persiste apenas dentro do ciclo de vida da sessão XCTest/UIAutomator).

### `web-login` — login manual

Para fluxos de autenticação que não podem ser automatizados (SSO, OAuth, MFA):

1. `AnalystWeb` abre um browser headed e navega para a URL
2. Emite `TESTPILOT_LOGIN_READY` no stdout
3. Aguarda `\n` no stdin (o macOS app envia via `saveSession()`)
4. Chama `browserContext.storageState(path = sessionPath)`
5. Emite `TESTPILOT_LOGIN_DONE:<path>` e fecha

---

## Plataforma Web (jvmMain)

O runtime web roda na JVM, separado dos targets iOS/Android. Playwright é a única dependência nova — toda a lógica de análise (`Analyst`, `TestAnalyst`, prompts, AI clients) é reusada de `commonMain` sem modificação.

### `AnalystDriverWeb`

Implementa `AnalystDriver` via Playwright for Java:

```kotlin
class AnalystDriverWeb(private val page: Page) : AnalystDriver {
    override suspend fun screenshotPng() = withContext(Dispatchers.IO) { page.screenshot() }
    override suspend fun tap(x, y)       = withContext(Dispatchers.IO) { page.mouse().click(x * 1280, y * 800) }
    override suspend fun scroll(dir)     = withContext(Dispatchers.IO) { page.mouse().wheel(0.0, if (dir == "down") 400.0 else -400.0) }
    override suspend fun type(x, y, t)   = withContext(Dispatchers.IO) { page.mouse().click(x * 1280, y * 800); page.keyboard().type(t) }
}
```

- Viewport fixo: 1280×800
- Todas as chamadas Playwright envolvidas em `withContext(Dispatchers.IO)` (API bloqueante)

### `WebSession`

Gerencia o arquivo de sessão (`~/.testpilot/sessions/<hostname>.json`):

- `sessionPath(url)`: extrai hostname via `java.net.URI`; lança `IllegalArgumentException` em URL inválida
- `loadContext(browser, url)`: cria `BrowserContext` com `storageState` se o arquivo existir
- `saveSession(context, url)`: persiste `storageState` após login bem-sucedido
- `interactiveLogin(url)`: abre browser headed, aguarda Enter, salva sessão

### `CachingAIClientJvm`

Decorator sobre qualquer `AIClient`, equivalente ao `CachingAIClient` de iOS:

- **Chave:** FNV-1a 64-bit sobre amostra do screenshot (stride 200) + prompt — idêntico ao iOS
- **Armazenamento:** `~/.testpilot/cache/<key>.json` via `java.io.File`
- **Concorrência:** flag de cache usa `AtomicBoolean` para garantir happens-before entre `Dispatchers.IO` e o contexto chamador

### `Main.kt`

Lê configuração exclusivamente via variáveis de ambiente (`TESTPILOT_*`), sem argumentos de linha de comando, para evitar problemas de escaping no shell:

| Variável | Uso |
|----------|-----|
| `TESTPILOT_MODE` | `analyze`, `test` ou `login` |
| `TESTPILOT_WEB_URL` | URL alvo |
| `TESTPILOT_OBJECTIVE` | Objetivo da análise/teste |
| `TESTPILOT_API_KEY` | Chave de API |
| `TESTPILOT_PROVIDER` | `anthropic` ou `openai` |
| `TESTPILOT_MAX_STEPS` | Limite de steps |
| `TESTPILOT_LANG` | `en` ou `pt-BR` |
| `TESTPILOT_OUTPUT` | Caminho do relatório (analyze) |
| `TESTPILOT_WEB_USERNAME` | Usuário para login automático |
| `TESTPILOT_WEB_PASSWORD` | Senha para login automático |

---

## Fluxo Android

O Android não tem a restrição de permissão do iOS — UIAutomator já tem acesso nativo para controlar apps e tirar screenshots.

**Entrypoint:** `AnalystAndroid.kt` roda como `@RunWith(AndroidJUnit4::class)` via `adb shell am instrument`.

**Driver:** `AnalystDriverAndroid.kt` usa `UiDevice` do UIAutomator.

**Coordenadas:** iOS usa coordenadas normalizadas (0.0–1.0) traduzidas internamente pela XCUICoordinate API. Android converte as mesmas coordenadas normalizadas multiplicando por `device.displayWidth` / `device.displayHeight`.

**Relatório:** salvo em `Context.getExternalFilesDir()`, recuperado via `adb pull`.

| | iOS | Android |
|---|---|---|
| Entrypoint | XCTest | AndroidJUnit4 (UIAutomator) |
| Screenshot | `XCUIScreen.mainScreen.screenshot()` | `UiDevice.takeScreenshot(file)` |
| Tap | `XCUICoordinate.tap()` | `UiDevice.click(x, y)` em pixels |
| Scroll | `XCUIApplication.swipeUp/Down()` | `UiDevice.swipe()` |
| Type | `XCUICoordinate.typeText()` | `Instrumentation.sendStringSync()` |
| Relatório | `NSTemporaryDirectory()` | `getExternalFilesDir()` |
| Providers | Anthropic, OpenAI, Gemini | Anthropic, OpenAI |

---

## Arquivos-chave

### Lógica compartilhada (`commonMain`)

| Arquivo | Responsabilidade |
|---------|-----------------|
| `analyst/Analyst.kt` | Loop exploratório: screenshot, stuck detection, chamada à IA, execução de ação |
| `analyst/TestAnalyst.kt` | Loop determinístico: termina em Pass/Fail; retorna `TestResult` |
| `analyst/AnalystDriver.kt` | Interface de driver (screenshot, tap, scroll, type) |
| `ai/VisionPrompt.kt` | Prompt para modo analyze (exploração livre) |
| `ai/TestVisionPrompt.kt` | Prompt para modo test (avaliador determinístico) |
| `analyst/AnalysisAction.kt` | Sealed class: Tap/Scroll/Type/Done/Pass/Fail + reparo de JSON truncado |
| `analyst/TestResult.kt` | `data class TestResult(passed, reason, steps)` |
| `analyst/HtmlReportWriter.kt` | Geração do HTML com screenshots inline (apenas modo analyze) |
| `runtime/Config.kt` | Data class + ConfigBuilder |

### iOS (`iosMain`)

| Arquivo | Responsabilidade |
|---------|-----------------|
| `analyst/AnalystIOS.kt` | Entrypoint analyze: login pre-step opcional; inicializa HttpClient(Darwin), AIClient; salva relatório |
| `analyst/TestAnalystIOS.kt` | Entrypoint test: login pre-step opcional; emite marcadores stdout; usa CachingAIClient |
| `ai/CachingAIClient.kt` | Decorator: FNV-1a hash key, NSCachesDirectory store |
| `analyst/AnalystDriverIOS.kt` | Implementa driver via XCUIApplication/XCUIScreen |
| `harness/AnalystTests/AnalystTests.swift` | Gerado pelo CLI; não versionar mudanças locais |

### Android (`androidMain`)

| Arquivo | Responsabilidade |
|---------|-----------------|
| `analyst/AnalystAndroid.kt` | Setup de instrumentação; login pre-step via `InstrumentationRegistry.getArguments()`; salva relatório |
| `analyst/AnalystDriverAndroid.kt` | Implementa driver via UiDevice |

### Web (`jvmMain`)

| Arquivo | Responsabilidade |
|---------|-----------------|
| `analyst/AnalystWeb.kt` | Entrypoint analyze: browser headed; login pre-step ou sessão carregada; emite `TESTPILOT_REPORT_PATH=` |
| `analyst/TestAnalystWeb.kt` | Entrypoint test: browser headless; login pre-step usa browser headed separado; CachingAIClientJvm |
| `analyst/AnalystDriverWeb.kt` | Implementa driver via Playwright for Java (viewport 1280×800) |
| `analyst/WebSession.kt` | `sessionPath()`, `loadContext()`, `saveSession()`, `interactiveLogin()` |
| `analyst/WebAIClientFactory.kt` | `buildWebAIClient()` — factory compartilhada entre AnalystWeb e TestAnalystWeb |
| `ai/CachingAIClientJvm.kt` | Decorator: FNV-1a hash key (idêntico ao iOS), armazenamento via `java.io.File` |
| `Main.kt` | Lê `TESTPILOT_*` env vars; despacha para AnalystWeb, TestAnalystWeb ou interactiveLogin |

### AI clients

| Arquivo | Responsabilidade |
|---------|-----------------|
| `ai/AnthropicChatClient.kt` | Integração com API Anthropic |
| `ai/OpenAIChatClient.kt` | Integração com API OpenAI (dual path: SDK + HTTP manual) |
| `ai/GeminiChatClient.kt` | Integração com API Gemini |

### Build & CLI

| Arquivo | Responsabilidade |
|---------|-----------------|
| `testpilot` | Script bash: parsing de args, detecção de device, build, execução, report; branches `ios`, `android`, `web`, `web-login` |
| `scripts/build_ios_sdk.sh` | Build do XCFramework; geração dos `.def` de cinterop |
| `sdk/testpilot/build.gradle.kts` | Configuração KMM: targets iOS/Android/JVM, dependências, tasks `runWebRunner` e `installPlaywrightBrowsers` |

---

## Defaults de configuração

```kotlin
object ConfigDefaults {
    const val maxTokens   = 200   // tokens por step (ação + observação)
    const val temperature = 0.0   // resposta determinística
    const val maxSteps    = 10    // profundidade de exploração padrão
}
```

O CLI sobrescreve `maxSteps` via `--max-steps` (padrão `20` no bash, sobrepõe o Kotlin default).

---

## Tratamento de erros

| Situação | Comportamento |
|----------|--------------|
| Build do SDK falha | Erro com instrução para rodar `scripts/build_ios_sdk.sh` manualmente |
| Relatório não gerado | Log do xcodebuild impresso; log completo salvo em `/tmp/testpilot_last_xcodebuild.log` |
| Bundle ID não encontrado | Lista apps disponíveis; seleção interativa se múltiplos matches |
| Simulador não inicializado | Mensagem de erro com comando de boot |
| Provisioning falha | Log do xcodebuild capturado para debug |
| JSON de ação truncado | `repairTruncatedJson()` tenta fechar o JSON; fallback para `done` se inválido |
| `maxSteps` atingido sem veredicto (test) | `FAIL: Test did not reach a conclusion within N steps` |
| Erro de leitura do cache | Log de aviso; continua sem cache (não fatal) |
| Erro de escrita do cache | Log de aviso; continua (não fatal) |
| Erro de IA no modo test | Propaga como `FAIL` com a mensagem de erro como motivo |
| URL inacessível (web) | Playwright lança exceção → `FAIL: Could not load URL` (test) ou erro CLI (analyze) |
| Sessão corrompida (web) | Log de aviso; continua sem sessão (não fatal) |
| Provider Gemini em plataforma web | Erro antecipado antes de abrir browser: `Gemini is not supported on web platform` |
| Processo `web-login` encerra antes de `LOGIN_READY` | `AnalysisRunner` transiciona para `.failed(error:)` com stderr do processo |

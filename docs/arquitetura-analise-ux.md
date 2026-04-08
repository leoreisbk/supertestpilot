# Arquitetura do modo de análise de UX — referência técnica

Este documento descreve o funcionamento interno do modo `analyze` do TestPilot. Destinado a engenheiros que precisam entender, manter ou estender o sistema.

---

## Visão geral

O TestPilot é um projeto **Kotlin Multiplatform (KMM)**. A lógica central de análise vive em `commonMain` e é compilada para iOS (XCFramework) e Android (AAR). O ponto de entrada é um script bash que orquestra o build, a injeção de configuração e a execução do teste.

```
testpilot (bash)
  └── build SDK (gradlew / build_ios_sdk.sh)
  └── gera AnalystTests.swift com config injetada
  └── xcodebuild test / adb instrument
        └── AnalystIOS / AnalystAndroid (Kotlin)
              └── Analyst.kt (loop compartilhado)
                    ├── AnalystDriver (screenshot, tap, scroll, type)
                    ├── AIClient (Anthropic / OpenAI / Gemini)
                    └── HtmlReportWriter → report.html
```

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
        is Done   → break
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

**Nota:** Gemini não está disponível no path Android. Apenas Anthropic e OpenAI funcionam lá.

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

## Prompts — `VisionPrompt.kt`

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
| `analyst/Analyst.kt` | Loop principal: screenshot, stuck detection, chamada à IA, execução de ação |
| `analyst/AnalystDriver.kt` | Interface de driver (screenshot, tap, scroll, type) |
| `ai/VisionPrompt.kt` | Montagem do prompt, envio à IA, parsing da resposta |
| `analyst/AnalysisAction.kt` | Sealed class para Tap/Scroll/Type/Done + reparo de JSON truncado |
| `analyst/HtmlReportWriter.kt` | Geração do HTML com screenshots inline |
| `runtime/Config.kt` | Data class + ConfigBuilder |

### iOS (`iosMain`)

| Arquivo | Responsabilidade |
|---------|-----------------|
| `analyst/AnalystIOS.kt` | Inicializa HttpClient(Darwin), AIClient; salva relatório |
| `analyst/AnalystDriverIOS.kt` | Implementa driver via XCUIApplication/XCUIScreen |
| `harness/AnalystTests/AnalystTests.swift` | Gerado pelo CLI; não versionar mudanças locais |

### Android (`androidMain`)

| Arquivo | Responsabilidade |
|---------|-----------------|
| `analyst/AnalystAndroid.kt` | Setup de instrumentação; salva relatório |
| `analyst/AnalystDriverAndroid.kt` | Implementa driver via UiDevice |

### AI clients

| Arquivo | Responsabilidade |
|---------|-----------------|
| `ai/AnthropicChatClient.kt` | Integração com API Anthropic |
| `ai/OpenAIChatClient.kt` | Integração com API OpenAI (dual path: SDK + HTTP manual) |
| `ai/GeminiChatClient.kt` | Integração com API Gemini |

### Build & CLI

| Arquivo | Responsabilidade |
|---------|-----------------|
| `testpilot` | Script bash: parsing de args, detecção de device, build, execução, report |
| `scripts/build_ios_sdk.sh` | Build do XCFramework; geração dos `.def` de cinterop |
| `sdk/testpilot/build.gradle.kts` | Configuração KMM: targets, frameworks, dependências |

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

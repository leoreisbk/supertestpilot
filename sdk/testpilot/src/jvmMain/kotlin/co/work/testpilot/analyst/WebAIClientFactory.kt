package co.work.testpilot.analyst

import co.work.testpilot.ai.AnthropicChatClient
import co.work.testpilot.ai.GeminiChatClient
import co.work.testpilot.ai.OpenAIChatClient
import co.work.testpilot.runtime.AIProvider
import co.work.testpilot.runtime.AIProviderDefaults
import co.work.testpilot.runtime.Config
import com.aallam.openai.api.logging.LogLevel
import com.aallam.openai.client.OpenAI
import com.aallam.openai.client.OpenAIConfig
import com.aallam.openai.client.OpenAIHost
import io.ktor.client.HttpClient

internal fun buildWebAIClient(cfg: Config, httpClient: HttpClient) = when (cfg.provider) {
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
    AIProvider.Gemini -> GeminiChatClient(
        apiKey = cfg.apiKey,
        modelId = cfg.modelId ?: AIProviderDefaults.geminiModel,
        httpClient = httpClient,
        apiHost = cfg.apiHost ?: "https://generativelanguage.googleapis.com",
    )
}

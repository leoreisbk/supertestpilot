package co.work.testpilot.runtime

import co.work.testpilot.AppUISnapshot
import co.work.testpilot.ai.AIClient
import co.work.testpilot.ai.AnthropicChatClient
import co.work.testpilot.ai.OpenAIChatClient
import co.work.testpilot.runtime.prompts.InstructPrompt
import co.work.testpilot.runtime.prompts.InstructPromptInput
import co.work.testpilot.runtime.prompts.SimplifyPrompt
import co.work.testpilot.runtime.prompts.SimplifyPromptInput
import co.work.testpilot.throwables.TestAutomationException
import co.work.testpilot.utils.EmbeddingElement
import co.work.testpilot.utils.EmbeddingUtils
import co.work.testpilot.utils.StringSimilarity
import com.aallam.openai.api.embedding.EmbeddingRequest
import com.aallam.openai.api.logging.LogLevel
import com.aallam.openai.api.model.ModelId
import com.aallam.openai.client.OpenAI
import com.aallam.openai.client.OpenAIConfig
import com.aallam.openai.client.OpenAIHost
import io.ktor.client.*
import io.ktor.client.engine.cio.*
import kotlin.coroutines.cancellation.CancellationException

class Runner(private val config: Config) {
    private val aiClient: AIClient = createAIClient(config)

    // OpenAI client kept for embedding-based fuzzy element matching.
    // null when provider is not OpenAI; fuzzy matching degrades gracefully.
    private val openAIForEmbeddings: OpenAI? = when (config.provider) {
        AIProvider.OpenAI -> buildOpenAIClient(config)
        AIProvider.Anthropic -> null
    }

    private val simplifyPrompt = SimplifyPrompt(aiClient, config)
    private val instructPrompt = InstructPrompt(aiClient, config)
    private var lastInstruction: String? = null

    @Throws(TestAutomationException::class, CancellationException::class)
    suspend fun getInstruction(objective: String, uiSnapshot: AppUISnapshot): String {
        val simplifiedUI = simplifyPrompt(SimplifyPromptInput(objective, uiSnapshot.toPromptString()))
        val instruction = instructPrompt(InstructPromptInput(objective, simplifiedUI, lastInstruction))
        lastInstruction = instruction
        return instruction
    }

    suspend fun searchEmbeddings(items: List<String>, query: String, n: Int = 1): List<String> {
        val client = openAIForEmbeddings
            ?: return StringSimilarity.search(items, query, n)

        val texts = items.filter { it.isNotBlank() }
        val embeddingModelId = ModelId("text-embedding-ada-002")

        val response = client.embeddings(
            EmbeddingRequest(
                model = embeddingModelId,
                input = texts + listOf(query),
            )
        )

        val elementEmbeddings = response.embeddings.dropLast(1)
        val queryEmbedding = response.embeddings.last()
        return EmbeddingUtils.search(
            document = elementEmbeddings.mapIndexed { index, embedding ->
                EmbeddingElement(embedding, texts[index])
            },
            query = queryEmbedding,
            n = n,
        )
    }
}

private fun createAIClient(config: Config): AIClient {
    val httpClient = HttpClient(CIO)
    return when (config.provider) {
        AIProvider.OpenAI -> OpenAIChatClient(
            openAI = buildOpenAIClient(config),
            modelId = config.modelId ?: AIProviderDefaults.openAIModel,
            httpClient = httpClient,
            apiKey = config.apiKey,
            apiHost = config.apiHost ?: "https://api.openai.com",
        )
        AIProvider.Anthropic -> AnthropicChatClient(
            apiKey = config.apiKey,
            modelId = config.modelId ?: AIProviderDefaults.anthropicModel,
            httpClient = httpClient,
            apiHost = config.apiHost ?: "https://api.anthropic.com",
            extraHeaders = config.apiHeaders,
        )
    }
}

private fun buildOpenAIClient(config: Config) = OpenAI(
    config = OpenAIConfig(
        token = config.apiKey,
        organization = config.apiOrg,
        headers = config.apiHeaders,
        host = config.apiHost?.let { OpenAIHost(it) } ?: OpenAIHost.OpenAI,
        logLevel = LogLevel.None,
    )
)

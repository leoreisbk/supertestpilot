package co.work.testpilot.runtime

import co.work.testpilot.AppUISnapshot
import co.work.testpilot.openai.OpenAIModel
import co.work.testpilot.runtime.prompts.InstructPrompt
import co.work.testpilot.runtime.prompts.InstructPromptInput
import co.work.testpilot.runtime.prompts.SimplifyPrompt
import co.work.testpilot.runtime.prompts.SimplifyPromptInput
import co.work.testpilot.throwables.TestAutomationException
import co.work.testpilot.utils.EmbeddingElement
import co.work.testpilot.utils.EmbeddingUtils
import com.aallam.openai.api.embedding.EmbeddingRequest
import com.aallam.openai.api.logging.LogLevel
import com.aallam.openai.api.model.ModelId
import com.aallam.openai.client.OpenAI
import com.aallam.openai.client.OpenAIConfig
import com.aallam.openai.client.OpenAIHost
import kotlin.coroutines.cancellation.CancellationException

class Runner(private val config: Config) {
    private val aiClient = OpenAI(config = OpenAIConfig(
        token = config.apiKey,
        organization = config.apiOrg,
        headers = config.apiHeaders,
        host = config.apiHost?.let { OpenAIHost(it) } ?: OpenAIHost.OpenAI,
        logLevel = LogLevel.None
    ))

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
        val texts = items.filter { it.isNotBlank() }

        // We append the query text to the embedding requests
        val response = aiClient.embeddings(
            EmbeddingRequest(
                model = ModelId(OpenAIModel.GPT3_TextEmbeddingAda002.idString),
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

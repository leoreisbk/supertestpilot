package co.work.testpilot

import co.work.testpilot.utils.EmbeddingElement
import co.work.testpilot.utils.EmbeddingUtils
import com.aallam.openai.api.BetaOpenAI
import com.aallam.openai.api.chat.ChatCompletionRequest
import com.aallam.openai.api.chat.ChatMessage
import com.aallam.openai.api.chat.ChatRole
import com.aallam.openai.api.completion.CompletionRequest
import com.aallam.openai.api.embedding.EmbeddingRequest
import com.aallam.openai.api.model.Model
import com.aallam.openai.api.model.ModelId
import com.aallam.openai.client.Models
import com.aallam.openai.client.OpenAI
import io.ktor.client.*
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

private enum class OpenAIModel(val idString: String) {
    GPT3_TextEmbeddingAda002("text-embedding-ada-002"),
    GPT3_TextDavinci003("text-davinci-003"),
    GPT4("gpt-4"),
    GPT4_0314("gpt-4-0314"),
}

class Runner(val config: Config) {
    val aiClient = OpenAI(token = config.apiKey)
    val serializer = Json { ignoreUnknownKeys = true }

    // TODO: add @Throws
    @OptIn(BetaOpenAI::class)
    suspend fun getCompletionResponse(ui: String, last: String?, objective: String): String? {
        val response = aiClient.chatCompletion(
            ChatCompletionRequest(
                model = ModelId(OpenAIModel.GPT4_0314.idString),
                messages = listOf(
                    ChatMessage(ChatRole.System, Prompts.system(objective)),
                    ChatMessage(ChatRole.User, Prompts.uiState(last = last, ui = ui)),
                ),
                temperature = config.temperature,
                n = 1,
                maxTokens = config.maxTokens,
            )
        )

        return response.choices.first().message?.content
    }

    // TODO: add @Throws
    @OptIn(BetaOpenAI::class)
    suspend fun splitIntoSteps(objective: String): List<String> {
        val response = aiClient.completion(
            CompletionRequest(
                model = ModelId(OpenAIModel.GPT3_TextDavinci003.idString),
                prompt = Prompts.stepsCompletion(objective),
                maxTokens = config.maxTokens,
                temperature = config.temperature,
                n = 1,
            )
        )

        return serializer.decodeFromString(response.choices.first().text)
    }

    // TODO: add @Throws
    suspend fun searchEmbeddings(input: String, query: String, n: Int = 1): List<String> {
        val texts = input
            .split("\n")
            .filter { it.isNotBlank() }

        val response = aiClient.embeddings(
            EmbeddingRequest(
                model = ModelId(OpenAIModel.GPT3_TextEmbeddingAda002.idString),
                input = texts + listOf(query),
            )
        )
        return EmbeddingUtils.search(
            document = response.embeddings
                .dropLast(1)
                .mapIndexed { index, embedding -> EmbeddingElement(embedding, texts[index]) },
            query = response.embeddings.last(),
            n = n,
        )
    }
}

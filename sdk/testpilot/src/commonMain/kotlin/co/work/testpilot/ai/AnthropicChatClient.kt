package co.work.testpilot.ai

import co.work.testpilot.Logging
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class AnthropicChatClient(
    private val apiKey: String,
    private val modelId: String,
    private val httpClient: HttpClient,
    private val apiHost: String = "https://api.anthropic.com",
    private val apiVersion: String = "2023-06-01",
    private val extraHeaders: Map<String, String> = emptyMap(),
) : AIClient {

    private val json = Json { ignoreUnknownKeys = true }

    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        maxTokens: Int,
        temperature: Double,
    ): String {
        // Anthropic requires system prompts as a top-level field, not a message role
        val systemContent = messages
            .filter { it.role == ChatMessage.ROLE_SYSTEM }
            .joinToString("\n") { it.content }
            .takeIf { it.isNotEmpty() }

        val userMessages = messages
            .filter { it.role != ChatMessage.ROLE_SYSTEM }
            .map { AnthropicMessage(role = it.role, content = it.content) }

        val request = AnthropicRequest(
            model = modelId,
            maxTokens = maxTokens,
            temperature = temperature,
            system = systemContent,
            messages = userMessages,
        )

        val body = json.encodeToString(request)
        Logging.info("=====\nCHAT REQUEST (Anthropic):\n=====\n$body")

        val response: HttpResponse = httpClient.post("$apiHost/v1/messages") {
            contentType(ContentType.Application.Json)
            header("x-api-key", apiKey)
            header("anthropic-version", apiVersion)
            extraHeaders.forEach { (key, value) -> header(key, value) }
            setBody(body)
        }

        val responseText = response.bodyAsText()
        Logging.info("=====\nCHAT RESPONSE (Anthropic):\n=====\n$responseText")

        val parsed = json.decodeFromString<AnthropicResponse>(responseText)
        return parsed.content.firstOrNull { it.type == "text" }?.text
            ?: throw IllegalStateException("Empty response from Anthropic: $responseText")
    }

    @Serializable
    private data class AnthropicRequest(
        val model: String,
        @SerialName("max_tokens") val maxTokens: Int,
        val temperature: Double,
        val system: String? = null,
        val messages: List<AnthropicMessage>,
    )

    @Serializable
    private data class AnthropicMessage(
        val role: String,
        val content: String,
    )

    @Serializable
    private data class AnthropicResponse(
        val content: List<AnthropicContent>,
    )

    @Serializable
    private data class AnthropicContent(
        val type: String,
        val text: String = "",
    )
}

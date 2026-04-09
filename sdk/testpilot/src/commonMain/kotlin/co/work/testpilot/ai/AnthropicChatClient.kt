package co.work.testpilot.ai

import co.work.testpilot.Logging
import io.ktor.client.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

class AnthropicChatClient(
    private val apiKey: String,
    private val modelId: String,
    private val httpClient: HttpClient,
    private val apiHost: String = "https://api.anthropic.com",
    private val apiVersion: String = "2023-06-01",
    private val extraHeaders: Map<String, String> = emptyMap(),
) : AIClient {

    private val json = Json { ignoreUnknownKeys = true }

    @OptIn(ExperimentalEncodingApi::class)
    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        maxTokens: Int,
        temperature: Double,
        imageBytes: ByteArray?,
    ): String {
        val systemContent = messages
            .filter { it.role == ChatMessage.ROLE_SYSTEM }
            .joinToString("\n") { it.content }
            .takeIf { it.isNotEmpty() }
            ?.let { listOf(AnthropicSystemBlock(text = it, cacheControl = AnthropicCacheControl())) }

        val nonSystemMessages = messages.filter { it.role != ChatMessage.ROLE_SYSTEM }

        val userMessages = nonSystemMessages.mapIndexed { index, msg ->
            val isLast = index == nonSystemMessages.lastIndex
            val contentBlocks: List<AnthropicContentBlock> = if (isLast && imageBytes != null) {
                listOf(
                    AnthropicContentBlock.Image(
                        source = AnthropicImageSource(
                            type = "base64",
                            mediaType = "image/png",
                            data = Base64.encode(imageBytes),
                        )
                    ),
                    AnthropicContentBlock.Text(text = msg.content),
                )
            } else {
                listOf(AnthropicContentBlock.Text(text = msg.content))
            }
            AnthropicMessage(role = msg.role, content = contentBlocks)
        }

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
            header("anthropic-beta", "prompt-caching-2024-07-31")
            extraHeaders.forEach { (key, value) -> header(key, value) }
            setBody(body)
        }

        val responseText = response.bodyAsText()
        Logging.info("=====\nCHAT RESPONSE (Anthropic):\n=====\n$responseText")

        val parsed = json.decodeFromString<AnthropicResponse>(responseText)
        if (parsed.type == "error") {
            val msg = parsed.error?.message ?: responseText
            throw IllegalStateException("Anthropic API error: $msg")
        }
        return parsed.content.firstOrNull { it.type == "text" }?.text
            ?: throw IllegalStateException("Empty response from Anthropic: $responseText")
    }

    @Serializable
    private data class AnthropicRequest(
        val model: String,
        @SerialName("max_tokens") val maxTokens: Int,
        val temperature: Double,
        val system: List<AnthropicSystemBlock>? = null,
        val messages: List<AnthropicMessage>,
    )

    @Serializable
    private data class AnthropicSystemBlock(
        val type: String = "text",
        val text: String,
        @SerialName("cache_control") val cacheControl: AnthropicCacheControl? = null,
    )

    @Serializable
    private data class AnthropicCacheControl(
        val type: String = "ephemeral",
    )

    @Serializable
    private data class AnthropicMessage(
        val role: String,
        val content: List<AnthropicContentBlock>,
    )

    @Serializable
    @OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
    @kotlinx.serialization.json.JsonClassDiscriminator("type")
    private sealed class AnthropicContentBlock {
        @Serializable
        @SerialName("text")
        data class Text(val text: String) : AnthropicContentBlock()

        @Serializable
        @SerialName("image")
        data class Image(val source: AnthropicImageSource) : AnthropicContentBlock()
    }

    @Serializable
    private data class AnthropicImageSource(
        val type: String,
        @SerialName("media_type") val mediaType: String,
        val data: String,
    )

    @Serializable
    private data class AnthropicResponse(
        val type: String = "",
        val content: List<AnthropicResponseContent> = emptyList(),
        val error: AnthropicErrorBody? = null,
    )

    @Serializable
    private data class AnthropicErrorBody(val type: String = "", val message: String = "")

    @Serializable
    private data class AnthropicResponseContent(
        val type: String,
        val text: String = "",
    )
}

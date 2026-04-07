@file:OptIn(com.aallam.openai.api.BetaOpenAI::class)

package co.work.testpilot.ai

import co.work.testpilot.Logging
import com.aallam.openai.api.BetaOpenAI
import com.aallam.openai.api.chat.ChatCompletionRequest
import com.aallam.openai.api.chat.ChatMessage as OpenAIChatMessage
import com.aallam.openai.api.chat.ChatRole
import com.aallam.openai.api.model.ModelId
import com.aallam.openai.client.OpenAI
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

class OpenAIChatClient(
    private val openAI: OpenAI,
    private val modelId: String,
    private val httpClient: HttpClient? = null,
    private val apiKey: String? = null,
    private val apiHost: String = "https://api.openai.com",
) : AIClient {

    private val json = Json { ignoreUnknownKeys = true }

    @OptIn(ExperimentalEncodingApi::class)
    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        maxTokens: Int,
        temperature: Double,
        imageBytes: ByteArray?,
    ): String {
        if (imageBytes != null) {
            val client = httpClient ?: throw IllegalStateException("httpClient required for vision")
            val key = apiKey ?: throw IllegalStateException("apiKey required for vision")

            val base64Image = Base64.encode(imageBytes)

            val openAIMessages = messages.mapIndexed { index, msg ->
                val isLast = index == messages.lastIndex
                val content: List<OpenAIContentBlock> = if (isLast && msg.role == ChatMessage.ROLE_USER) {
                    listOf(
                        OpenAIContentBlock.ImageUrl(
                            imageUrl = OpenAIImageUrl(url = "data:image/png;base64,$base64Image")
                        ),
                        OpenAIContentBlock.Text(text = msg.content),
                    )
                } else {
                    listOf(OpenAIContentBlock.Text(text = msg.content))
                }
                OpenAIRequestMessage(role = msg.role, content = content)
            }

            val request = OpenAIVisionRequest(
                model = modelId,
                messages = openAIMessages,
                maxTokens = maxTokens,
                temperature = temperature,
            )

            val body = json.encodeToString(request)
            Logging.info("=====\nCHAT REQUEST (OpenAI vision):\n=====\n$body")

            val response: HttpResponse = client.post("$apiHost/v1/chat/completions") {
                contentType(ContentType.Application.Json)
                header("Authorization", "Bearer $key")
                setBody(body)
            }

            val responseText = response.bodyAsText()
            Logging.info("=====\nCHAT RESPONSE (OpenAI vision):\n=====\n$responseText")

            val parsed = json.decodeFromString<OpenAIVisionResponse>(responseText)
            return parsed.choices.firstOrNull()?.message?.content
                ?: throw IllegalStateException("Empty response from OpenAI: $responseText")
        }

        val request = ChatCompletionRequest(
            model = ModelId(modelId),
            messages = messages.map { msg ->
                OpenAIChatMessage(
                    role = when (msg.role) {
                        ChatMessage.ROLE_SYSTEM -> ChatRole.System
                        ChatMessage.ROLE_ASSISTANT -> ChatRole.Assistant
                        else -> ChatRole.User
                    },
                    content = msg.content,
                )
            },
            temperature = temperature,
            n = 1,
            maxTokens = maxTokens,
        )

        Logging.info("=====\nCHAT REQUEST (OpenAI):\n=====\n" +
            messages.joinToString("\n") { "${it.role}: ${it.content}" })

        val response = openAI.chatCompletion(request)
        val content = response.choices.first().message?.content ?: ""

        Logging.info("=====\nCHAT RESPONSE (OpenAI):\n=====\n$content")

        return content
    }

    @Serializable
    private data class OpenAIVisionRequest(
        val model: String,
        val messages: List<OpenAIRequestMessage>,
        @SerialName("max_tokens") val maxTokens: Int,
        val temperature: Double,
    )

    @Serializable
    private data class OpenAIRequestMessage(
        val role: String,
        val content: List<OpenAIContentBlock>,
    )

    @Serializable
    @OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
    @kotlinx.serialization.json.JsonClassDiscriminator("type")
    private sealed class OpenAIContentBlock {
        @Serializable
        @SerialName("text")
        data class Text(val text: String) : OpenAIContentBlock()

        @Serializable
        @SerialName("image_url")
        data class ImageUrl(
            @SerialName("image_url") val imageUrl: OpenAIImageUrl,
        ) : OpenAIContentBlock()
    }

    @Serializable
    private data class OpenAIImageUrl(
        val url: String,
    )

    @Serializable
    private data class OpenAIVisionResponse(
        val choices: List<OpenAIVisionChoice>,
    )

    @Serializable
    private data class OpenAIVisionChoice(
        val message: OpenAIVisionMessage,
    )

    @Serializable
    private data class OpenAIVisionMessage(
        val content: String? = null,
    )
}

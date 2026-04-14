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

class GeminiChatClient(
    private val apiKey: String,
    private val modelId: String,
    private val httpClient: HttpClient,
    private val apiHost: String = "https://generativelanguage.googleapis.com",
) : AIClient {

    private val json = Json { ignoreUnknownKeys = true }

    @OptIn(ExperimentalEncodingApi::class)
    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        maxTokens: Int,
        temperature: Double,
        imageBytes: ByteArray?,
    ): String {
        val systemMessage = messages
            .filter { it.role == ChatMessage.ROLE_SYSTEM }
            .joinToString("\n") { it.content }
            .takeIf { it.isNotEmpty() }

        val nonSystemMessages = messages.filter { it.role != ChatMessage.ROLE_SYSTEM }

        val contents = nonSystemMessages.mapIndexed { index, msg ->
            val isLast = index == nonSystemMessages.lastIndex
            val parts: List<GeminiPart> = if (isLast && imageBytes != null) {
                listOf(
                    GeminiPart(inlineData = GeminiInlineData(
                        mimeType = imageBytes.imageMimeType(),
                        data = Base64.encode(imageBytes),
                    )),
                    GeminiPart(text = msg.content),
                )
            } else {
                listOf(GeminiPart(text = msg.content))
            }
            val role = if (msg.role == ChatMessage.ROLE_ASSISTANT) "model" else "user"
            GeminiContent(role = role, parts = parts)
        }

        val request = GeminiRequest(
            contents = contents,
            systemInstruction = systemMessage?.let {
                GeminiSystemInstruction(parts = listOf(GeminiPart(text = it)))
            },
            generationConfig = GeminiGenerationConfig(
                maxOutputTokens = maxTokens,
                temperature = temperature,
            ),
        )

        val body = json.encodeToString(request)
        Logging.info("=====\nCHAT REQUEST (Gemini):\n=====\n$body")

        val response: HttpResponse = httpClient.post(
            "$apiHost/v1beta/models/$modelId:generateContent?key=$apiKey"
        ) {
            contentType(ContentType.Application.Json)
            setBody(body)
        }

        val responseText = response.bodyAsText()
        Logging.info("=====\nCHAT RESPONSE (Gemini):\n=====\n$responseText")

        val parsed = json.decodeFromString<GeminiResponse>(responseText)

        if (parsed.error != null) {
            throw IllegalStateException("Gemini API error: ${parsed.error.message}")
        }

        return parsed.candidates?.firstOrNull()
            ?.content?.parts?.firstOrNull { it.text != null }?.text
            ?: throw IllegalStateException("Empty response from Gemini: $responseText")
    }

    @Serializable
    private data class GeminiRequest(
        val contents: List<GeminiContent>,
        @SerialName("system_instruction") val systemInstruction: GeminiSystemInstruction? = null,
        @SerialName("generationConfig") val generationConfig: GeminiGenerationConfig? = null,
    )

    @Serializable
    private data class GeminiSystemInstruction(
        val parts: List<GeminiPart>,
    )

    @Serializable
    private data class GeminiContent(
        val role: String,
        val parts: List<GeminiPart>,
    )

    // Gemini parts use field presence (not a type discriminator) to distinguish text vs image
    @Serializable
    private data class GeminiPart(
        val text: String? = null,
        @SerialName("inline_data") val inlineData: GeminiInlineData? = null,
    )

    @Serializable
    private data class GeminiInlineData(
        @SerialName("mime_type") val mimeType: String,
        val data: String,
    )

    @Serializable
    private data class GeminiGenerationConfig(
        @SerialName("maxOutputTokens") val maxOutputTokens: Int,
        val temperature: Double,
    )

    @Serializable
    private data class GeminiResponse(
        val candidates: List<GeminiCandidate>? = null,
        val error: GeminiError? = null,
    )

    @Serializable
    private data class GeminiCandidate(
        val content: GeminiContent,
    )

    @Serializable
    private data class GeminiError(
        val message: String = "",
    )
}

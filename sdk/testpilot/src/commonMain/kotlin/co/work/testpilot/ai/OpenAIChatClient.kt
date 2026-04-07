@file:OptIn(com.aallam.openai.api.BetaOpenAI::class)

package co.work.testpilot.ai

import co.work.testpilot.Logging
import com.aallam.openai.api.BetaOpenAI
import com.aallam.openai.api.chat.ChatCompletionRequest
import com.aallam.openai.api.chat.ChatMessage as OpenAIChatMessage
import com.aallam.openai.api.chat.ChatRole
import com.aallam.openai.api.model.ModelId
import com.aallam.openai.client.OpenAI

class OpenAIChatClient(
    private val openAI: OpenAI,
    private val modelId: String,
) : AIClient {

    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        maxTokens: Int,
        temperature: Double,
    ): String {
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
}

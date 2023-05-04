@file:OptIn(BetaOpenAI::class)

package co.work.testpilot.runtime.prompts

import co.work.testpilot.runtime.Config
import co.work.testpilot.runtime.Element
import com.aallam.openai.api.BetaOpenAI
import com.aallam.openai.api.chat.ChatCompletionRequest
import com.aallam.openai.api.chat.ChatMessage
import com.aallam.openai.api.chat.ChatRole
import com.aallam.openai.api.model.ModelId
import com.aallam.openai.client.OpenAI

private const val ENABLE_SIMPLIFY_PROMPT = false

data class SimplifyPromptInput(val objective: String, val formattedUI: String)

class SimplifyPrompt(client: OpenAI, config: Config) : OpenAIPrompt<SimplifyPromptInput, String>(client, config) {
    override suspend fun run(input: SimplifyPromptInput): String {
        if (!ENABLE_SIMPLIFY_PROMPT) {
            return uiState(input.formattedUI)
        }

        val request = ChatCompletionRequest(
            model = ModelId(OpenAIModel.GPT3_5_Turbo_0301.idString),
            messages = listOf(
                ChatMessage(ChatRole.System, system),
                ChatMessage(ChatRole.User, objective(input.objective)),
                ChatMessage(ChatRole.User, uiState(input.formattedUI)),
            ),
            temperature = config.temperature,
            n = 1,
            maxTokens = config.maxTokens,
        )
        val response = client.testPilotChatCompletion(request)
        return response.firstCompletionContent ?: ""
    }

    private companion object {
        val system = """
            As a mobile app agent, you have an objective and a simplified UI description. 
            You must remove all of the UI elements from the description that are not likely to be useful in accomplishing the objective.
            You need not output anything besides the remaining elements.
        """.trimIndent()

        fun objective(objective: String) = "OBJECTIVE: $objective"

        fun uiState(ui: String) = ui
    }
}
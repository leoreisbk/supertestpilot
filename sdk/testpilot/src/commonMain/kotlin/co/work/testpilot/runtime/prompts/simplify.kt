package co.work.testpilot.runtime.prompts

import co.work.testpilot.ai.AIClient
import co.work.testpilot.ai.ChatMessage
import co.work.testpilot.runtime.Config

private const val ENABLE_SIMPLIFY_PROMPT = false

data class SimplifyPromptInput(val objective: String, val formattedUI: String)

class SimplifyPrompt(client: AIClient, config: Config) : AIPrompt<SimplifyPromptInput, String>(client, config) {
    override suspend fun run(input: SimplifyPromptInput): String {
        if (!ENABLE_SIMPLIFY_PROMPT) {
            return input.formattedUI
        }

        val messages = listOf(
            ChatMessage(ChatMessage.ROLE_SYSTEM, system),
            ChatMessage(ChatMessage.ROLE_USER, objective(input.objective)),
            ChatMessage(ChatMessage.ROLE_USER, input.formattedUI),
        )
        return client.chatCompletion(
            messages = messages,
            maxTokens = config.maxTokens,
            temperature = config.temperature,
        )
    }

    private companion object {
        val system = """
            As a mobile app agent, you have an objective and a simplified UI description.
            You must remove all of the UI elements from the description that are not likely to be useful in accomplishing the objective.
            You need not output anything besides the remaining elements.
        """.trimIndent()

        fun objective(objective: String) = "OBJECTIVE: $objective"
    }
}

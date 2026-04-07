package co.work.testpilot.ai

import co.work.testpilot.analyst.AnalysisAction
import co.work.testpilot.runtime.Config

class VisionPrompt(
    private val aiClient: AIClient,
    private val config: Config,
) {
    suspend operator fun invoke(
        objective: String,
        screenshotPng: ByteArray,
        observationsSoFar: List<String>,
    ): AnalysisAction {
        val observationsText = if (observationsSoFar.isEmpty()) {
            "None yet."
        } else {
            observationsSoFar.mapIndexed { i, obs -> "${i + 1}. $obs" }.joinToString("\n")
        }

        val systemPrompt = """
            You are a UX analyst for mobile apps. You receive a screenshot and reason about usability, friction, and clarity.
            Respond ONLY with a single JSON object — no explanation, no markdown, no extra text.
        """.trimIndent()

        val userPrompt = """
            Objective: $objective

            Observations so far:
            $observationsText

            Look at the screenshot and decide what to do next.

            Respond with a JSON object with these fields:
            - action: "tap", "scroll", "type", or "done"
            - x, y: relative screen coordinates (0.0–1.0) for tap or type actions (omit for scroll/done)
            - direction: "up" or "down" for scroll actions (omit otherwise)
            - text: string to type for type actions (omit otherwise)
            - observation: a single sentence about something notable you see on this screen related to UX quality (can be null if nothing notable)
            - reason: why you are taking this action

            Use "done" when the objective is complete or you have gathered enough observations.

            Example response:
            {"action":"tap","x":0.5,"y":0.72,"observation":"The checkout button has low contrast and may be hard to spot","reason":"proceeding to checkout"}
        """.trimIndent()

        val messages = listOf(
            ChatMessage(role = ChatMessage.ROLE_SYSTEM, content = systemPrompt),
            ChatMessage(role = ChatMessage.ROLE_USER, content = userPrompt),
        )

        val response = aiClient.chatCompletion(
            messages = messages,
            maxTokens = maxOf(config.maxTokens, 1024),
            temperature = config.temperature,
            imageBytes = screenshotPng,
        )

        return try {
            AnalysisAction.parse(response)
        } catch (e: Exception) {
            AnalysisAction.Done(observation = "Could not parse AI response: ${e.message}")
        }
    }
}

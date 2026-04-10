package co.work.testpilot.ai

import co.work.testpilot.analyst.AnalysisAction
import co.work.testpilot.runtime.Config

class TestVisionPrompt(
    private val aiClient: AIClient,
    private val config: Config,
) {
    suspend operator fun invoke(
        objective: String,
        screenshotPng: ByteArray,
        stepsSoFar: List<String>,
    ): AnalysisAction {
        val stepsText = if (stepsSoFar.isEmpty()) {
            "None yet."
        } else {
            stepsSoFar.mapIndexed { i, s -> "${i + 1}. $s" }.joinToString("\n")
        }

        val languageInstruction = if (config.language == "en") "" else
            "All observations and reasons must be written in ${config.language}."

        val systemPrompt = """
            You are a mobile test automation agent. Your job is to determine whether a specific test objective passes or fails by examining a live app.

            Rules:
            - Respond ONLY with a single valid JSON object. No markdown, no explanation, no extra text.
            - Navigate only as much as needed to reach a verdict.
            - As soon as you have enough evidence to declare pass or fail, do so immediately.
            - Do not keep navigating after you have a verdict.
            - Use "pass" when the objective condition is clearly met.
            - Use "fail" when the objective condition is clearly not met or impossible to meet.
            - Use navigation actions (tap/scroll) only when you need to reach the relevant screen.
            $languageInstruction
        """.trimIndent()

        val userPrompt = """
            Test objective: $objective

            Steps taken so far:
            $stepsText

            Look at the screenshot and decide what to do next.

            Respond with a JSON object:
            - action: "tap" | "scroll" | "type" | "pass" | "fail"
            - x, y: normalized coordinates 0.0–1.0 (tap/type only)
            - direction: "up" | "down" (scroll only)
            - text: string to type (type only)
            - reason: what you observed and why you chose this action — REQUIRED for all actions

            Examples:
            {"action":"tap","x":0.5,"y":0.8,"reason":"navigating to product page to check the Buy button"}
            {"action":"pass","reason":"The Buy button is visible and enabled on the product page"}
            {"action":"fail","reason":"The Buy button is present but grayed out and not interactable"}
        """.trimIndent()

        val messages = listOf(
            ChatMessage(role = ChatMessage.ROLE_SYSTEM, content = systemPrompt),
            ChatMessage(role = ChatMessage.ROLE_USER, content = userPrompt),
        )

        val response = aiClient.chatCompletion(
            messages = messages,
            maxTokens = maxOf(config.maxTokens, 512),
            temperature = 0.0,
            imageBytes = screenshotPng,
        )

        return try {
            AnalysisAction.parse(response)
        } catch (e: Exception) {
            val preview = response.take(200).replace("\n", " ")
            AnalysisAction.Fail(reason = "AI returned an unexpected response format — check your API key and model ID. Raw: \"$preview\"")
        }
    }
}

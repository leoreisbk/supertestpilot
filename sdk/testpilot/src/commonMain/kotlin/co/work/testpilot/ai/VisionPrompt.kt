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
        stuckCount: Int = 0,
    ): AnalysisAction {
        val observationsText = if (observationsSoFar.isEmpty()) {
            "None yet."
        } else {
            observationsSoFar.mapIndexed { i, obs -> "${i + 1}. $obs" }.joinToString("\n")
        }

        val languageInstruction = if (config.language == "en") "" else
            "All observations, reasons, and summaries must be written in ${config.language}."

        val systemPrompt = """
            You are an expert mobile UX analyst. Your job is to explore a live app, gather usability evidence, and identify friction points.

            Rules:
            - Respond ONLY with a single valid JSON object. No markdown, no explanation, no extra text.
            - Each observation must be a unique, specific insight. Never repeat or rephrase an observation already listed.
            - Observations should name concrete UX issues (e.g. low contrast, missing feedback, confusing label) or positives — not generic statements.
            - Navigate actively: tap into flows, open menus, go deeper. One screen is never enough.
            - If you are on a detail or sub-screen, navigate back to explore other areas of the app.
            - Do not tap the same element twice in a row.
            $languageInstruction
        """.trimIndent()

        val screensSeen = observationsSoFar.size

        val stuckNote = when {
            stuckCount >= 3 -> "WARNING: You have been on this exact screen for $stuckCount steps in a row. You MUST navigate away — tap a back button, swipe, or scroll to a different screen. Do not repeat the same action."
            stuckCount >= 1 -> "You appear to be on the same screen as the previous step. Try a different action to move forward."
            else -> ""
        }

        val explorationNote = if (screensSeen < 5)
            "You have visited $screensSeen screen(s). Keep exploring — open menus, tap list items, go into sub-flows. Do NOT use \"done\" until you have visited at least 5 distinct screens."
        else
            "You have visited $screensSeen screens. Call \"done\" only after covering the main flows."

        val userPrompt = """
            Objective: $objective

            Observations already recorded (do NOT repeat or rephrase these):
            $observationsText

            $stuckNote
            $explorationNote

            Look at the screenshot and decide what to do next.

            Respond with a JSON object:
            - action: "tap" | "scroll" | "type" | "done"
            - x, y: normalized coordinates 0.0–1.0 (tap/type only)
            - direction: "up" | "down" (scroll only)
            - text: string to type (type only)
            - observation: one specific UX insight about this screen, or null if nothing new to note
            - reason: brief explanation of your action

            Example:
            {"action":"tap","x":0.5,"y":0.72,"observation":"CTA button blends into background — low contrast ratio","reason":"navigating to checkout to inspect payment flow"}
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
            val preview = response.take(200).replace("\n", " ")
            AnalysisAction.Done(observation = "AI returned an unexpected response format — check your API key and model ID. Raw: \"$preview\"")
        }
    }
}

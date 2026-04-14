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
        accessibilityTree: String = "",
    ): AnalysisAction {
        val observationsText = if (observationsSoFar.isEmpty()) {
            "None yet."
        } else {
            observationsSoFar.mapIndexed { i, obs -> "${i + 1}. $obs" }.joinToString("\n")
        }

        val languageInstruction = if (config.language == "en") "" else
            "All observations, reasons, and summaries must be written in ${config.language}."

        val systemPrompt = """
            You are a senior UX researcher conducting a structured usability evaluation of a live mobile app. Your findings will be used by product managers and designers to make product decisions — they must be specific, evidence-based, and actionable.

            ## Your job
            Explore the app with a clear focus on the stated objective. Gather evidence that directly informs whether the app succeeds or fails at that objective. Every observation must be something a PM or designer can act on.

            ## Observation quality standards
            - **Specific**: Name the exact element, screen, or flow (e.g. "Checkout → Payment screen: 'Confirm' button is below the fold on smaller devices")
            - **Evidence-based**: Describe what you actually saw (e.g. "Error message reads 'Something went wrong' with no recovery path")
            - **Actionable**: State the problem clearly enough that a designer knows what to fix
            - **No generics**: Never write "navigation could be improved" — write "Back button is missing on the Order Details screen, requiring users to swipe to go back"
            - **Severity**: Prefix critical blockers with [CRITICAL], friction points with [ISSUE], and positive UX patterns worth noting with [POSITIVE]

            ## Navigation rules
            - Stay focused on the objective — explore flows directly related to what you're evaluating
            - Use "type" — NOT "tap" — for text fields, search bars, or any input that accepts keyboard text. Always include a realistic value
            - Never tap the same element twice without a visible change
            - If stuck, scroll or navigate back to find a new path

            Respond ONLY with a single valid JSON object. No markdown, no explanation, no extra text.
            $languageInstruction
        """.trimIndent()

        val screensSeen = observationsSoFar.size

        val stuckNote = when {
            stuckCount >= 3 -> "WARNING: You have been on this exact screen for $stuckCount steps in a row. You MUST navigate away — tap a back button, swipe, or scroll to a different screen. Do not repeat the same action."
            stuckCount >= 1 -> "You appear to be on the same screen as the previous step. Try a different action to move forward."
            else -> ""
        }

        val explorationNote = if (screensSeen < 5)
            "You have visited $screensSeen screen(s). Keep exploring flows relevant to the objective — open menus, tap list items, go into sub-flows. Do NOT use \"done\" until you have visited at least 5 distinct screens."
        else
            "You have visited $screensSeen screens. Call \"done\" only after covering the main flows relevant to the objective."

        val treeSection = if (accessibilityTree.isNotEmpty())
            "\nUI Element Tree (use to identify element types — TextField requires \"type\", Button requires \"tap\", check disabled/enabled state):\n$accessibilityTree"
        else ""

        val userPrompt = """
            Evaluation objective: $objective

            Observations already recorded (do NOT repeat or rephrase these):
            $observationsText

            $stuckNote
            $explorationNote
            $treeSection
            Look at the screenshot. Identify one specific UX finding relevant to the objective, then decide your next navigation step.

            Respond with a JSON object:
            - action: "tap" | "scroll" | "type" | "done"
            - x, y: normalized coordinates 0.0–1.0 (tap/type only)
            - direction: "up" | "down" (scroll only)
            - text: string to type (type only)
            - observation: one UX finding with [CRITICAL]/[ISSUE]/[POSITIVE] prefix — what you saw and why it matters for the objective. Null only if the screen adds nothing new.
            - reason: where you're navigating next and why it's relevant to the objective

            Examples:
            {"action":"tap","x":0.5,"y":0.72,"observation":"[ISSUE] Checkout → Cart screen: 'Proceed' button label is vague — users may not understand it triggers payment","reason":"navigating to payment screen to inspect the full checkout flow"}
            {"action":"type","x":0.5,"y":0.3,"text":"john@example.com","observation":"[POSITIVE] Login screen: email field auto-focuses on load, reducing friction for returning users","reason":"filling email to proceed to the main app flow"}
            {"action":"scroll","direction":"down","observation":"[CRITICAL] Profile screen: Save button is not visible without scrolling — changes may be lost","reason":"scrolling to check if save button is reachable"}
            {"action":"done","observation":null,"reason":"covered all main flows relevant to the objective"}
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

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
        accessibilityTree: String = "",
    ): AnalysisAction {
        val stepsText = if (stepsSoFar.isEmpty()) {
            "None yet."
        } else {
            stepsSoFar.mapIndexed { i, s -> "${i + 1}. $s" }.joinToString("\n")
        }

        val languageInstruction = if (config.language == "en") "" else
            "All observations and reasons must be written in ${config.language}."

        val systemPrompt = """
            You are a mobile test automation agent. Your job is to navigate a live app and determine whether a test objective passes or fails.

            Action rules — follow these exactly:
            - Use "tap" to press buttons, select items, open menus, or navigate.
            - Use "type" — NOT "tap" — whenever interacting with a text field, search bar, name field, or any input that accepts keyboard text. Always include a "text" value with a realistic test value (e.g. "Aspirin" for a medicine name, "500mg" for dosage, "2" for quantity).
            - Use "scroll" when content or form fields are hidden below or above the visible area. When a keyboard is open, scroll up to reveal fields hidden behind it.
            - Use "pass" as soon as the objective is clearly and fully met — do not keep navigating.
            - Use "fail" when the objective is clearly impossible, when a required element is absent, or when you have been trying for many steps without any progress.

            Anti-loop rules:
            - Read your step history carefully. If you see the same description repeated 3 or more times, you are stuck in a loop — try a completely different action immediately, or issue "fail".
            - Never tap or type on the same element more than twice without visible progress.
            - If a form field is not accepting input after two attempts, scroll to find another approach or issue "fail".
            - [LOOP WARNING] entries in step history are injected by the system — treat them as hard directives to change strategy.

            Respond ONLY with a single valid JSON object. No markdown, no explanation, no extra text.
            $languageInstruction
        """.trimIndent()

        val treeSection = if (accessibilityTree.isNotEmpty())
            "\nUI Element Tree (use this to identify element types — TextField requires \"type\", Button requires \"tap\"):\n$accessibilityTree"
        else ""

        val userPrompt = """
            Test objective: $objective

            Steps taken so far:
            $stepsText
            $treeSection
            Look at the screenshot and decide what to do next.

            Respond with a JSON object:
            - action: "tap" | "scroll" | "type" | "pass" | "fail"
            - x, y: normalized coordinates 0.0–1.0 (tap/type only)
            - direction: "up" | "down" (scroll only)
            - text: string to type (type only)
            - reason: what you observed and why you chose this action — REQUIRED for all actions

            Examples:
            {"action":"tap","x":0.95,"y":0.08,"reason":"tapping + button to open new medicine form"}
            {"action":"type","x":0.5,"y":0.3,"text":"Aspirin","reason":"filling the medicine name field"}
            {"action":"type","x":0.5,"y":0.5,"text":"500mg","reason":"filling the dosage field"}
            {"action":"scroll","direction":"up","reason":"keyboard is covering form fields, scrolling to reveal them"}
            {"action":"pass","reason":"form was filled and saved successfully — medicine appears in the list"}
            {"action":"fail","reason":"save button is disabled after filling all fields"}
        """.trimIndent()

        val messages = listOf(
            ChatMessage(role = ChatMessage.ROLE_SYSTEM, content = systemPrompt),
            ChatMessage(role = ChatMessage.ROLE_USER, content = userPrompt),
        )

        val response = aiClient.chatCompletion(
            messages = messages,
            maxTokens = maxOf(config.maxTokens, 512),
            temperature = config.temperature,
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

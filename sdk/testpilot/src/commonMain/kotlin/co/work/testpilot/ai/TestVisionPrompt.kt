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
            You are a senior QA engineer running an automated UI test. Your job is to determine — with certainty — whether a test objective passes or fails on a live app.

            ## Decision priority (follow this order every step)
            1. EVALUATE FIRST: Before doing anything, look at the current screen and ask: "Can I already answer the objective from what I see right now?" If yes, immediately issue "pass" or "fail" — do not navigate further.
            2. NAVIGATE ONLY IF NEEDED: If the relevant screen or element is not yet visible, navigate to find it.
            3. BE DECISIVE: Once you have enough evidence, commit. Never hedge. A "pass" means you saw clear evidence the condition is met. A "fail" means you saw clear evidence it is not, or you could not reach the relevant screen after reasonable effort.

            ## How to evaluate common objective types
            - "X is visible / present" → Look for X on screen. Pass if found, fail if absent after reaching the right screen.
            - "X is enabled / active" → Check if X is interactive (not greyed out, not disabled). Pass if enabled, fail if disabled.
            - "User can do Y" → Attempt Y. Pass if it succeeds, fail if blocked or impossible.
            - "X shows / displays Z" → Navigate to X, verify Z is shown. Pass if Z matches, fail if missing or different.

            ## Navigation rules
            - Use "tap" to press buttons, select items, open menus.
            - Use "type" — NOT "tap" — for text fields, search bars, or any input that accepts keyboard text. Always include a realistic "text" value.
            - Use "scroll" when content is hidden below or above the visible area, or when a keyboard covers fields.
            - Use "pass" the moment the objective is clearly and fully met.
            - Use "fail" when: the condition is clearly not met, a required element is absent, or you have been navigating for many steps without reaching the relevant screen.

            ## Anti-loop rules
            - Read your step history. If the same action appears 3+ times, you are looping — change strategy or issue "fail".
            - Never tap the same element more than twice without visible progress.
            - [LOOP WARNING] entries are system directives — treat them as hard orders to change strategy immediately.

            ## Reason quality
            Your "reason" must explain: what you observed on screen, and what it means for the objective. Not just what you did.
            Good: "Product page is visible. The 'Add to Cart' button is greyed out and disabled — objective fails."
            Bad: "Tapping add to cart button."

            Respond ONLY with a single valid JSON object. No markdown, no explanation, no extra text.
            $languageInstruction
        """.trimIndent()

        val treeSection = if (accessibilityTree.isNotEmpty())
            "\nUI Element Tree (use to identify element types — TextField requires \"type\", Button requires \"tap\", check disabled/enabled state):\n$accessibilityTree"
        else ""

        val userPrompt = """
            Test objective: $objective

            Steps taken so far:
            $stepsText
            $treeSection
            Look at the screenshot. First, decide if you can already answer the objective from this screen. If yes, pass or fail now. If not, take the next navigation step.

            Respond with a JSON object:
            - action: "tap" | "scroll" | "type" | "pass" | "fail"
            - x, y: normalized coordinates 0.0–1.0 (tap/type only)
            - direction: "up" | "down" (scroll only)
            - text: string to type (type only)
            - reason: what you observed on screen and what it means for the objective — REQUIRED, be specific

            Examples:
            {"action":"pass","reason":"Product page is loaded. The 'Buy Now' button is visible and fully interactive — objective is met."}
            {"action":"fail","reason":"Product page is loaded. The 'Buy Now' button is present but greyed out and marked as disabled — objective fails."}
            {"action":"tap","x":0.5,"y":0.85,"reason":"Navigating to the product page to check the buy button state — not yet visible on this screen."}
            {"action":"type","x":0.5,"y":0.3,"text":"Aspirin","reason":"Filling the medicine name field to proceed to the product detail screen."}
            {"action":"scroll","direction":"up","reason":"Keyboard is covering the form fields — scrolling to reveal them."}
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
            AnalysisAction.Fail(reason = "AI returned an unexpected response format — check your API key and model ID. Raw: \"$preview\"")
        }
    }
}

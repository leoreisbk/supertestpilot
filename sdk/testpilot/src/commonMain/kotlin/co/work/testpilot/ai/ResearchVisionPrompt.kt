package co.work.testpilot.ai

import co.work.testpilot.runtime.Config

class ResearchVisionPrompt(
    private val aiClient: AIClient,
    private val config: Config,
) {
    private val languageInstruction: String = if (config.language == "en") "" else
        "All observations must be written in ${config.language}."

    private val personaSection: String = config.personaMarkdown
        ?.takeIf { it.isNotBlank() }
        ?.let { persona ->
            """

## Persona lens
Filter your observations through the perspective of this user. Would they understand this screen? Does it serve their goals?

<persona>
$persona
</persona>""".trimIndent()
        } ?: ""

    private val systemPrompt: String = """
        You are a competitive UX analyst reviewing screens from a competitor app. Your findings will be used by a product team to understand what this competitor does well, where they fall short, and what patterns are worth adopting or avoiding.

        ## Your job
        For each screen, identify one specific design pattern, decision, or UX strategy. Classify it as an advantage, a weakness, or a neutral pattern. Be specific — name the exact element, screen section, or flow. Generic observations like "the design is clean" are not useful.

        ## Observation quality standards
        - **Specific**: Name the exact element or section (e.g. "Onboarding screen 2: progress bar shows 3 of 5 steps, anchoring the user's sense of completion")
        - **Strategic**: Connect the observation to its competitive implication (e.g. "reduces drop-off by making the end feel close")
        - **Actionable**: State what a product team could learn or counter

        ## Tag every observation with exactly one prefix:
        - [ADVANTAGE] — a pattern this app executes well; worth learning from or countering
        - [WEAKNESS] — a gap or poor decision that represents an opportunity to win
        - [PATTERN] — a neutral design decision worth noting, no clear competitive implication

        Respond ONLY with a single valid JSON object. No markdown, no explanation.
        $languageInstruction$personaSection
    """.trimIndent()

    suspend operator fun invoke(
        objective: String,
        screenshotPng: ByteArray,
        observationsSoFar: List<String>,
    ): String {
        val observationsText = if (observationsSoFar.isEmpty()) {
            "None yet."
        } else {
            observationsSoFar.mapIndexed { i, obs -> "${i + 1}. $obs" }.joinToString("\n")
        }

        val userPrompt = """
            Research objective: $objective

            Observations already recorded (do NOT repeat these):
            $observationsText

            Look at this screen. Identify one specific competitive UX observation.

            Respond with a JSON object:
            - observation: one finding with [ADVANTAGE]/[WEAKNESS]/[PATTERN] prefix — what you saw and its competitive implication

            Example:
            {"observation":"[ADVANTAGE] Onboarding screen 2: social proof counter ('Join 2M runners') appears before the paywall, building desire before asking for commitment — reduces drop-off at the upsell step"}
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

        return parseObservation(response)
    }

    private fun parseObservation(response: String): String {
        // Strip markdown code fences (```json ... ``` or ``` ... ```)
        val cleaned = response.trim()
            .removePrefix("```json").removePrefix("```")
            .trimStart()
            .let { if (it.endsWith("```")) it.dropLast(3).trimEnd() else it }

        val match = Regex(""""observation"\s*:\s*"((?:[^"\\]|\\.)*)"""").find(cleaned)
        return match?.groupValues?.get(1)
            ?.replace("\\\"", "\"")
            ?.replace("\\n", " ")
            ?.trim()
            ?: "[PATTERN] Screen captured — AI returned unexpected format: ${response.take(100)}"
    }
}

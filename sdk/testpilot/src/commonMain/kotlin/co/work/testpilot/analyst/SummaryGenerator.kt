package co.work.testpilot.analyst

import co.work.testpilot.ai.AIClient
import co.work.testpilot.ai.ChatMessage
import co.work.testpilot.runtime.Config

internal suspend fun generateSummary(
    aiClient: AIClient,
    config: Config,
    objective: String,
    steps: List<AnalysisStep>,
): String {
    val observations = steps.mapNotNull { it.observation }.distinct()
    if (observations.isEmpty()) return "No observations recorded."

    val languageInstruction = if (config.language == "en") "" else
        "Write your entire response in ${config.language}."

    val personaContext = if (config.personaMarkdown.isNullOrBlank()) "" else """

This evaluation was conducted from the perspective of:
<persona>
${config.personaMarkdown}
</persona>

Frame your findings through the lens of this persona's goals and pain points.""".trimIndent()

    val prompt = """
        You conducted a UX evaluation of a mobile app with this objective: "$objective"

        Raw observations from the session:
        ${observations.mapIndexed { i, obs -> "${i + 1}. $obs" }.joinToString("\n")}

        Write a structured evaluation report for a product team (PMs, designers, QA leads). Format it exactly as follows:

        **Overall verdict**: One sentence stating whether the app succeeds or fails at the objective and why.

        **Critical issues** (blockers that prevent the objective from being met — list only if any exist):
        - [item]

        **Friction points** (problems that make the objective harder but not impossible):
        - [item]

        **Positive patterns** (things the app does well related to the objective — list only if any exist):
        - [item]

        **Recommendation**: One concrete next step the team should prioritize.

        Be specific. Each bullet must name the screen/flow and the concrete problem or pattern. Do not generalize.
        $languageInstruction$personaContext
    """.trimIndent()

    return aiClient.chatCompletion(
        messages = listOf(
            ChatMessage(role = ChatMessage.ROLE_SYSTEM, content = "You are a senior UX researcher writing a structured product evaluation. Be specific, evidence-based, and actionable."),
            ChatMessage(role = ChatMessage.ROLE_USER, content = prompt),
        ),
        maxTokens = 800,
        temperature = 0.0,
    )
}

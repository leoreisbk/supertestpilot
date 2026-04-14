package co.work.testpilot.analyst

import co.work.testpilot.ai.AIClient
import co.work.testpilot.ai.ChatMessage
import co.work.testpilot.ai.VisionPrompt
import co.work.testpilot.runtime.Config
import kotlin.time.TimeSource

class Analyst(
    private val driver: AnalystDriver,
    private val aiClient: AIClient,
    private val config: Config,
) {
    suspend fun run(
        objective: String,
        onStep: ((String) -> Unit)? = null,
    ): AnalysisReport {
        val mark = TimeSource.Monotonic.markNow()
        val steps = mutableListOf<AnalysisStep>()
        val seenObservations = mutableSetOf<String>()
        val visionPrompt = VisionPrompt(aiClient, config)
        var done = false
        var stuckCount = 0
        var lastFingerprint = Int.MIN_VALUE
        var scrollRecoveryCount = 0

        for (i in 0 until config.maxSteps) {
            if (done) break
            val (screenshot, tree) = driver.captureStep()
            val fp = screenFingerprint(screenshot)

            stuckCount = if (fp == lastFingerprint) stuckCount + 1 else 0
            lastFingerprint = fp

            // Hard recovery: alternate scroll direction so repeated recoveries don't
            // cancel each other out (e.g. stuck at top: up would do nothing).
            if (stuckCount >= 5) {
                val direction = if (scrollRecoveryCount % 2 == 0) "up" else "down"
                driver.scroll(direction)
                scrollRecoveryCount++
                stuckCount = 0
                continue
            }

            val observationsSoFar = steps.mapNotNull { it.observation }.takeLast(10)
            val action = visionPrompt(objective, screenshot, observationsSoFar, stuckCount, tree)

            val obs = action.observation
            if (obs != null && seenObservations.add(obs)) {
                steps.add(
                    AnalysisStep(
                        screenshotData = screenshot,
                        observation = obs,
                        action = action.actionName,
                        coordinates = action.coordinates,
                    )
                )
                onStep?.invoke(obs)
            }

            when (action) {
                is AnalysisAction.Done -> done = true
                is AnalysisAction.Pass, is AnalysisAction.Fail -> done = true
                is AnalysisAction.Tap -> driver.tap(action.x, action.y)
                is AnalysisAction.Scroll -> driver.scroll(action.direction)
                is AnalysisAction.Type -> driver.type(action.x, action.y, action.text)
            }
        }

        val summary = generateSummary(objective, steps)
        val durationMs = mark.elapsedNow().inWholeMilliseconds

        return AnalysisReport(
            objective = objective,
            summary = summary,
            stepCount = steps.size,
            durationMs = durationMs,
            steps = steps,
            persona = config.personaMarkdown,
        )
    }

    private suspend fun generateSummary(objective: String, steps: List<AnalysisStep>): String {
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
}

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
    suspend fun run(objective: String): AnalysisReport {
        val mark = TimeSource.Monotonic.markNow()
        val steps = mutableListOf<AnalysisStep>()
        val visionPrompt = VisionPrompt(aiClient, config)
        var done = false

        for (i in 0 until config.maxSteps) {
            if (done) break
            val screenshot = driver.screenshotPng()
            val observationsSoFar = steps.mapNotNull { it.observation }
            val action = visionPrompt(objective, screenshot, observationsSoFar)

            steps.add(
                AnalysisStep(
                    screenshotData = screenshot,
                    observation = action.observation,
                    action = action.actionName,
                    coordinates = action.coordinates,
                )
            )

            when (action) {
                is AnalysisAction.Done -> done = true
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
        )
    }

    private suspend fun generateSummary(objective: String, steps: List<AnalysisStep>): String {
        val observations = steps.mapNotNull { it.observation }
        if (observations.isEmpty()) return "No observations recorded."

        val prompt = """
            You analyzed a mobile app with the following objective: "$objective"

            These are your observations from the session:
            ${observations.mapIndexed { i, obs -> "${i + 1}. $obs" }.joinToString("\n")}

            Write a concise 2–4 sentence summary of the overall UX quality based on these observations.
            Focus on the most important friction points and positive aspects.
        """.trimIndent()

        return aiClient.chatCompletion(
            messages = listOf(
                ChatMessage(role = ChatMessage.ROLE_SYSTEM, content = "You are a UX analyst. Be concise and direct."),
                ChatMessage(role = ChatMessage.ROLE_USER, content = prompt),
            ),
            maxTokens = 300,
            temperature = 0.0,
        )
    }
}

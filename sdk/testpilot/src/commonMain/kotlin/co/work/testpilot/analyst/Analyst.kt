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
    // Lightweight fingerprint: sample every 200th byte to detect identical screens.
    private fun fingerprint(png: ByteArray): Int {
        var sum = 0
        var i = 0
        while (i < png.size) { sum += png[i].toInt(); i += 200 }
        return sum
    }

    suspend fun run(objective: String): AnalysisReport {
        val mark = TimeSource.Monotonic.markNow()
        val steps = mutableListOf<AnalysisStep>()
        val visionPrompt = VisionPrompt(aiClient, config)
        var done = false
        var stuckCount = 0
        var lastFingerprint = Int.MIN_VALUE

        for (i in 0 until config.maxSteps) {
            if (done) break
            val screenshot = driver.screenshotPng()
            val fp = fingerprint(screenshot)

            stuckCount = if (fp == lastFingerprint) stuckCount + 1 else 0
            lastFingerprint = fp

            // Hard recovery: force a scroll back after 5 consecutive identical screens.
            if (stuckCount >= 5) {
                driver.scroll("up")
                stuckCount = 0
                continue
            }

            val observationsSoFar = steps.mapNotNull { it.observation }
            val action = visionPrompt(objective, screenshot, observationsSoFar, stuckCount)

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
        val observations = steps.mapNotNull { it.observation }.distinct()
        if (observations.isEmpty()) return "No observations recorded."

        val languageInstruction = if (config.language == "en") "" else
            "Write your response in ${config.language}."

        val prompt = """
            You analyzed a mobile app with the following objective: "$objective"

            These are your observations from the session:
            ${observations.mapIndexed { i, obs -> "${i + 1}. $obs" }.joinToString("\n")}

            Write a concise 2–4 sentence summary of the overall UX quality based on these observations.
            Focus on the most important friction points and positive aspects.
            $languageInstruction
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

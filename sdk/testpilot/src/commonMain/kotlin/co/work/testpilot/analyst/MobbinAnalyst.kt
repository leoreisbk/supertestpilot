package co.work.testpilot.analyst

import co.work.testpilot.ai.AIClient
import co.work.testpilot.ai.ResearchVisionPrompt
import co.work.testpilot.runtime.Config
import kotlin.time.TimeSource

class MobbinAnalyst(
    private val aiClient: AIClient,
    private val config: Config,
) {
    suspend fun run(
        images: List<ByteArray>,
        objective: String,
        onStep: ((String) -> Unit)? = null,
    ): AnalysisReport {
        val mark = TimeSource.Monotonic.markNow()
        val steps = mutableListOf<AnalysisStep>()
        val prompt = ResearchVisionPrompt(aiClient, config)

        for (image in images) {
            val observationsSoFar = steps.mapNotNull { it.observation }
            val observation = prompt(objective, image, observationsSoFar)
            steps.add(
                AnalysisStep(
                    screenshotData = image,
                    observation = observation,
                    action = "analyzed",
                    coordinates = null,
                )
            )
            onStep?.invoke(observation)
        }

        val summary = generateSummary(aiClient, config, objective, steps)
        val durationMs = mark.elapsedNow().inWholeMilliseconds

        return AnalysisReport(
            objective = objective,
            summary = summary,
            stepCount = steps.size,
            durationMs = durationMs,
            steps = steps,
            persona = config.personaMarkdown,
            source = "mobbin",
        )
    }
}

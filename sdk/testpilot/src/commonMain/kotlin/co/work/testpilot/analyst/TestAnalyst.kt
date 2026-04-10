package co.work.testpilot.analyst

import co.work.testpilot.ai.AIClient
import co.work.testpilot.ai.TestVisionPrompt
import co.work.testpilot.runtime.Config

class TestAnalyst(
    private val driver: AnalystDriver,
    private val aiClient: AIClient,
    private val config: Config,
) {
    private fun fingerprint(png: ByteArray): Int {
        var sum = 0
        var i = 0
        while (i < png.size) { sum += png[i].toInt(); i += 200 }
        return sum
    }

    suspend fun run(
        objective: String,
        onStep: ((message: String) -> Unit)? = null,
    ): TestResult {
        val prompt = TestVisionPrompt(aiClient, config)
        val steps = mutableListOf<String>()
        var stuckCount = 0
        var lastFingerprint = Int.MIN_VALUE

        for (i in 0 until config.maxSteps) {
            val screenshot = driver.screenshotPng()
            val fp = fingerprint(screenshot)

            stuckCount = if (fp == lastFingerprint) stuckCount + 1 else 0
            lastFingerprint = fp

            if (stuckCount >= 5) {
                val reason = "Stuck — screen unchanged for 5 consecutive steps"
                onStep?.invoke(reason)
                return TestResult(passed = false, reason = reason, steps = steps)
            }

            val action = prompt(objective, screenshot, steps)

            when (action) {
                is AnalysisAction.Pass -> {
                    onStep?.invoke(action.reason)
                    steps.add(action.reason)
                    return TestResult(passed = true, reason = action.reason, steps = steps)
                }
                is AnalysisAction.Fail -> {
                    onStep?.invoke(action.reason)
                    steps.add(action.reason)
                    return TestResult(passed = false, reason = action.reason, steps = steps)
                }
                is AnalysisAction.Done -> {
                    val msg = action.observation ?: "Analysis complete without verdict"
                    onStep?.invoke(msg)
                    steps.add(msg)
                    return TestResult(passed = false, reason = "No verdict reached", steps = steps)
                }
                is AnalysisAction.Tap -> {
                    val msg = action.reason ?: "Tapped at (${action.x}, ${action.y})"
                    onStep?.invoke(msg)
                    steps.add(msg)
                    driver.tap(action.x, action.y)
                }
                is AnalysisAction.Scroll -> {
                    val msg = action.reason ?: "Scrolled ${action.direction}"
                    onStep?.invoke(msg)
                    steps.add(msg)
                    driver.scroll(action.direction)
                }
                is AnalysisAction.Type -> {
                    val msg = action.reason ?: "Typed text"
                    onStep?.invoke(msg)
                    steps.add(msg)
                    driver.type(action.x, action.y, action.text)
                }
            }
        }

        return TestResult(
            passed = false,
            reason = "Test did not reach a conclusion within ${config.maxSteps} steps",
            steps = steps,
        )
    }
}

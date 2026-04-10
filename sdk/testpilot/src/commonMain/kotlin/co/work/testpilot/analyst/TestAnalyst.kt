package co.work.testpilot.analyst

import co.work.testpilot.ai.AIClient
import co.work.testpilot.ai.TestVisionPrompt
import co.work.testpilot.runtime.Config

class TestAnalyst(
    private val driver: AnalystDriver,
    private val aiClient: AIClient,
    private val config: Config,
) {
    suspend fun run(
        objective: String,
        onStep: ((message: String) -> Unit)? = null,
    ): TestResult {
        val prompt = TestVisionPrompt(aiClient, config)
        val steps = mutableListOf<String>()
        var stuckCount = 0
        var lastFingerprint = Int.MIN_VALUE
        var scrollRecoveryCount = 0

        for (i in 0 until config.maxSteps) {
            val screenshot = driver.screenshotPng()
            val fp = screenFingerprint(screenshot)

            stuckCount = if (fp == lastFingerprint) stuckCount + 1 else 0
            lastFingerprint = fp

            if (stuckCount >= 5) {
                if (scrollRecoveryCount >= 3) {
                    val reason = "Stuck — screen unchanged after recovery attempts"
                    onStep?.invoke(reason)
                    return TestResult(passed = false, reason = reason, steps = steps)
                }
                val direction = if (scrollRecoveryCount % 2 == 0) "up" else "down"
                driver.scroll(direction)
                scrollRecoveryCount++
                stuckCount = 0
                continue
            }

            val tree = driver.accessibilityTree()
            val action = prompt(objective, screenshot, steps, tree)

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

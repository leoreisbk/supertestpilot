package co.work.testpilot.analyst

import co.work.testpilot.ai.AIClient
import co.work.testpilot.ai.TestVisionPrompt
import co.work.testpilot.runtime.Config
import kotlin.math.abs

class TestAnalyst(
    private val driver: AnalystDriver,
    private val aiClient: AIClient,
    private val config: Config,
) {
    private data class TapPoint(val x: Double, val y: Double)

    suspend fun run(
        objective: String,
        onStep: ((message: String) -> Unit)? = null,
    ): TestResult {
        val prompt = TestVisionPrompt(aiClient, config)
        val steps = mutableListOf<String>()
        var stuckCount = 0
        var lastFingerprint = Int.MIN_VALUE
        var scrollRecoveryCount = 0
        val recentTaps = ArrayDeque<TapPoint>()

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
                    injectLoopWarningIfNeeded(recentTaps, action.x, action.y, steps, onStep)
                    trackTap(recentTaps, action.x, action.y)
                    val msg = action.reason ?: "Tapped at (${action.x}, ${action.y})"
                    onStep?.invoke(msg)
                    steps.add(msg)
                    driver.tap(action.x, action.y)
                }
                is AnalysisAction.Scroll -> {
                    recentTaps.clear() // scroll breaks tap patterns
                    val msg = action.reason ?: "Scrolled ${action.direction}"
                    onStep?.invoke(msg)
                    steps.add(msg)
                    driver.scroll(action.direction)
                }
                is AnalysisAction.Type -> {
                    recentTaps.clear() // typing breaks tap patterns
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

    private fun trackTap(recentTaps: ArrayDeque<TapPoint>, x: Double, y: Double) {
        if (recentTaps.size >= 8) recentTaps.removeFirst()
        recentTaps.addLast(TapPoint(x, y))
    }

    private fun injectLoopWarningIfNeeded(
        recentTaps: ArrayDeque<TapPoint>,
        x: Double,
        y: Double,
        steps: MutableList<String>,
        onStep: ((String) -> Unit)?,
    ) {
        val repeats = recentTaps.count { abs(it.x - x) < 0.05 && abs(it.y - y) < 0.05 }
        if (repeats >= 3) {
            val warning = "[LOOP WARNING] Same target tapped ${repeats + 1} times — change strategy immediately"
            steps.add(warning)
            onStep?.invoke(warning)
        }
    }
}

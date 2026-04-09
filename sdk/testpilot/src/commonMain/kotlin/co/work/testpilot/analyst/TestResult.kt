package co.work.testpilot.analyst

data class TestResult(
    val passed: Boolean,
    val reason: String,
    val steps: List<String>,
)

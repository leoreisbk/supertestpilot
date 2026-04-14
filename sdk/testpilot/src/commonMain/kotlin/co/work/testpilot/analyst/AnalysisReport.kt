package co.work.testpilot.analyst

data class AnalysisReport(
    val objective: String,
    val summary: String,
    val stepCount: Int,
    val durationMs: Long,
    val steps: List<AnalysisStep>,
    val persona: String? = null,
)

package co.work.testpilot.analyst

data class AnalysisStep(
    val screenshotData: ByteArray,
    val observation: String?,
    val action: String,
    val coordinates: Pair<Double, Double>?,
)

package co.work.testpilot

data class Config(
    val apiKey: String,
    val maxTokens: Int,
    val temperature: Double,
    val maxSteps: Int,
)

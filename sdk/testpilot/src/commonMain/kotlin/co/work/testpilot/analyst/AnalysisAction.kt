package co.work.testpilot.analyst

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

sealed class AnalysisAction {
    abstract val observation: String?

    data class Tap(
        val x: Double,
        val y: Double,
        override val observation: String?,
        val reason: String?,
    ) : AnalysisAction()

    data class Scroll(
        val direction: String,
        override val observation: String?,
        val reason: String?,
    ) : AnalysisAction()

    data class Type(
        val x: Double,
        val y: Double,
        val text: String,
        override val observation: String?,
        val reason: String?,
    ) : AnalysisAction()

    data class Done(
        override val observation: String?,
    ) : AnalysisAction()

    val actionName: String
        get() = when (this) {
            is Tap -> "tap"
            is Scroll -> "scroll"
            is Type -> "type"
            is Done -> "done"
        }

    val coordinates: Pair<Double, Double>?
        get() = when (this) {
            is Tap -> Pair(x, y)
            is Type -> Pair(x, y)
            else -> null
        }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun parse(jsonString: String): AnalysisAction {
            // Strip markdown code fences if present
            val clean = jsonString
                .trim()
                .removePrefix("```json")
                .removePrefix("```")
                .removeSuffix("```")
                .trim()

            val raw = json.decodeFromString<RawAction>(clean)
            return when (raw.action) {
                "tap" -> Tap(
                    x = raw.x ?: 0.5,
                    y = raw.y ?: 0.5,
                    observation = raw.observation,
                    reason = raw.reason,
                )
                "scroll" -> Scroll(
                    direction = raw.direction ?: "down",
                    observation = raw.observation,
                    reason = raw.reason,
                )
                "type" -> Type(
                    x = raw.x ?: 0.5,
                    y = raw.y ?: 0.5,
                    text = raw.text ?: "",
                    observation = raw.observation,
                    reason = raw.reason,
                )
                "done" -> Done(observation = raw.observation)
                else -> Done(observation = "Unknown action: ${raw.action}")
            }
        }
    }

    @Serializable
    private data class RawAction(
        val action: String,
        val x: Double? = null,
        val y: Double? = null,
        val direction: String? = null,
        val text: String? = null,
        val observation: String? = null,
        val reason: String? = null,
    )
}

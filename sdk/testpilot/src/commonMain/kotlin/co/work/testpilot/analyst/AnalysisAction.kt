package co.work.testpilot.analyst

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

    data class Pass(
        val reason: String,
    ) : AnalysisAction() {
        override val observation: String? get() = null
    }

    data class Fail(
        val reason: String,
    ) : AnalysisAction() {
        override val observation: String? get() = null
    }

    val actionName: String
        get() = when (this) {
            is Tap -> "tap"
            is Scroll -> "scroll"
            is Type -> "type"
            is Done -> "done"
            is Pass -> "pass"
            is Fail -> "fail"
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
            val clean = jsonString
                .trim()
                .removePrefix("```json")
                .removePrefix("```")
                .removeSuffix("```")
                .trim()

            val raw = try {
                json.decodeFromString<RawAction>(clean)
            } catch (_: Exception) {
                json.decodeFromString<RawAction>(repairTruncatedJson(clean))
            }
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
                "pass" -> Pass(reason = raw.reason ?: "Test passed")
                "fail" -> Fail(reason = raw.reason ?: "Test failed")
                else -> Done(observation = "Unknown action: ${raw.action}")
            }
        }

        private fun repairTruncatedJson(s: String): String {
            if (s.endsWith("}")) return s
            var depth = 0
            var inString = false
            var escaped = false
            var lastSafeComma = -1
            for (i in s.indices) {
                val c = s[i]
                if (escaped) { escaped = false; continue }
                if (c == '\\' && inString) { escaped = true; continue }
                if (c == '"') { inString = !inString; continue }
                if (inString) continue
                if (c == '{') depth++
                if (c == '}') depth--
                if (c == ',' && depth == 1) lastSafeComma = i
            }
            return if (lastSafeComma != -1) {
                s.substring(0, lastSafeComma) + "}"
            } else {
                s.substringBefore(",") + "}"
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

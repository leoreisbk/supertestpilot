package co.work.testpilot

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class PersistenceManagerAndroid(
    context: Context,
    val objective: String
) : PersistenceManager {
    private val sharedPreferences = context.getSharedPreferences(Constants.sharedPreferencesKey, Context.MODE_PRIVATE)
    private var currentSteps: MutableList<String?> = mutableListOf()
    private val serializer = Json { ignoreUnknownKeys = true }

    private val knownStepsForObjective: List<String?> get() {
        val objectiveStepsJson = sharedPreferences.getString(objective, null)
        return objectiveStepsJson?.let(serializer::decodeFromString) ?: emptyList()
    }

    override fun getStep(index: Int): String? {
        val steps = knownStepsForObjective

        return if (steps.isNotEmpty() && steps.size > index) {
            steps[index]
        } else {
            null
        }
    }

    override fun recordStep(value: String?) {
        currentSteps.add(value)
    }

    override fun persistSteps() {
        if (currentSteps.isNotEmpty()) {
            // SharedPreferences does not support writing arrays, so we serialize it as a JSON object.
            sharedPreferences.edit()
                .putString(objective, serializer.encodeToString(currentSteps))
                .commit()
        }
    }
}

private object Constants {
    const val sharedPreferencesKey = "TestPilotSteps"
}

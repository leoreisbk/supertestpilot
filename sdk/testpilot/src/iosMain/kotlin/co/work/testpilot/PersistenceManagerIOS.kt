package co.work.testpilot

import co.work.testpilot.runtime.Instruction
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import platform.Foundation.NSUserDefaults

class PersistenceManagerIOS(private val objective: String) : PersistenceManager {
    private var currentSteps: MutableList<String?> = mutableListOf()
    private val objectiveMap get() = NSUserDefaults.standardUserDefaults.objectForKey(
        Constants.userDefaultsKey
    ) as? Map<String, List<String?>> ?: emptyMap()

    private val knownStepsForObjective: List<String?> get() = objectiveMap[objective] ?: emptyList()
    private val serializer = Json { ignoreUnknownKeys = true }

    override fun getStep(index: Int): Instruction? {
        val steps = knownStepsForObjective
        val stepString = steps.getOrNull(index) ?: return null

        return serializer.decodeFromString(stepString)
    }

    override fun recordStep(value: String?) {
        currentSteps.add(value)
    }

    override fun persistSteps() {
        if (currentSteps.isNotEmpty()) {
            NSUserDefaults.standardUserDefaults.setObject(
                objectiveMap + mapOf(objective to currentSteps),
                forKey = Constants.userDefaultsKey
            )
        }
    }

    override fun clear() {
        currentSteps.clear()
        NSUserDefaults.standardUserDefaults.setObject(
            objectiveMap.filterKeys { it != this.objective },
            forKey = Constants.userDefaultsKey
        )
    }

    override fun isEmpty() = knownStepsForObjective.isEmpty()
}

private object Constants {
    const val userDefaultsKey = "TestPilotSteps"
}

package co.work.testpilot

import platform.Foundation.NSUserDefaults

class PersistenceManagerIOS(private val objective: String) : PersistenceManager {
    private var currentSteps: MutableList<String?> = mutableListOf()

    private val knownStepsForObjective: List<String?>
        get() {
            val allTests = NSUserDefaults.standardUserDefaults.objectForKey(Constants.userDefaultsKey) as? Map<String, List<String?>>
            return allTests?.get(objective) ?: emptyList()
        }

    init {
        addObjectiveIfRequired()
    }

    private fun addObjectiveIfRequired() {
        val userDefaults = NSUserDefaults.standardUserDefaults
        val existingDict = userDefaults.objectForKey(Constants.userDefaultsKey) as? Map<String, List<String?>>

        if (existingDict == null) {
            userDefaults.setObject(mapOf(objective to listOf<String?>()), forKey = Constants.userDefaultsKey)
        }
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
        val allTests = NSUserDefaults.standardUserDefaults.objectForKey(Constants.userDefaultsKey) as? Map<String, List<String?>>
        if (allTests != null && currentSteps.isNotEmpty()) {
            NSUserDefaults.standardUserDefaults.setObject(
                allTests + mapOf(objective to currentSteps),
                forKey = Constants.userDefaultsKey
            )
        }
    }
}

private object Constants {
    const val userDefaultsKey = "TestPilotSteps"
}

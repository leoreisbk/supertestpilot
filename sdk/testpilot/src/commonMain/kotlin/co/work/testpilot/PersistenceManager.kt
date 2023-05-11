package co.work.testpilot

interface PersistenceManager {
    fun getStep(index: Int): String?
    fun recordStep(value: String?)
    fun persistSteps()
    fun clear()
    fun isEmpty(): Boolean
}

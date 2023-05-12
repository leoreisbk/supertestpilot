package co.work.testpilot

import co.work.testpilot.runtime.Instruction

interface PersistenceManager {
    fun getStep(index: Int): Instruction?
    fun recordStep(value: String?)
    fun persistSteps()
    fun clear()
    fun isEmpty(): Boolean
}

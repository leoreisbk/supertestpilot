package co.work.testpilot

import co.work.testpilot.runtime.ElementType

interface AppUIElementSnapshot {
    val type: ElementType
    val label: String
}

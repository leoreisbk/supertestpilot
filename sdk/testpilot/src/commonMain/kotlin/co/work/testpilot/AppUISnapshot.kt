package co.work.testpilot

interface AppUISnapshot {
    fun toPromptString(): String
    val allElements: List<AppUIElementSnapshot>
}

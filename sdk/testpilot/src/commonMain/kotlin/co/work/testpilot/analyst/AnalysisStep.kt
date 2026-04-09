package co.work.testpilot.analyst

data class AnalysisStep(
    val screenshotData: ByteArray,
    val observation: String?,
    val action: String,
    val coordinates: Pair<Double, Double>?,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AnalysisStep) return false
        return screenshotData.contentEquals(other.screenshotData) &&
            observation == other.observation &&
            action == other.action &&
            coordinates == other.coordinates
    }

    override fun hashCode(): Int {
        var result = screenshotData.contentHashCode()
        result = 31 * result + (observation?.hashCode() ?: 0)
        result = 31 * result + action.hashCode()
        result = 31 * result + (coordinates?.hashCode() ?: 0)
        return result
    }
}

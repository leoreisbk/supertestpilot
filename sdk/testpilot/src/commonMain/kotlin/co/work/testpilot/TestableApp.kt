package co.work.testpilot

interface TestableApp<Snapshot: AppUISnapshot> {
    suspend fun launch()
    suspend fun snapshot(): Snapshot
}

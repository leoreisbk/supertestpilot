package co.work.testpilot

interface TestActor<Snapshot: AppUISnapshot, App: TestableApp<Snapshot>> {
    suspend fun performInstruction(
        runner: Runner,
        app: App,
        instruction: Instruction.Actionable,
        uiSnapshot: Snapshot,
    )
}

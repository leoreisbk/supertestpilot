package co.work.testpilot

import co.work.testpilot.runtime.Instruction
import co.work.testpilot.runtime.Runner

interface TestActor<Snapshot: AppUISnapshot, App: TestableApp<Snapshot>> {
    suspend fun performInstruction(
        runner: Runner,
        app: App,
        instruction: Instruction.Actionable,
        uiSnapshot: Snapshot,
    )
}

package co.work.testpilot

import co.work.testpilot.runtime.Instruction
import co.work.testpilot.runtime.Runner

class TestActorAndroid : TestActor<AppUISnapshotAndroid, TestableAppAndroid> {
    override suspend fun performInstruction(
        runner: Runner,
        app: TestableAppAndroid,
        instruction: Instruction.Actionable,
        uiSnapshot: AppUISnapshotAndroid,
    ) {
        when (instruction) {
            is Instruction.Type -> {
                // TODO
            }
            is Instruction.Tap -> {
                // TODO
            }
            is Instruction.ScrollUp -> {
                // TODO
            }
            is Instruction.ScrollDown -> {
                // TODO
            }
            is Instruction.GoBack -> {
                app.device.pressBack()
            }
        }
        app.device.waitForWindowUpdate(app.packageName, 5000)
    }
}

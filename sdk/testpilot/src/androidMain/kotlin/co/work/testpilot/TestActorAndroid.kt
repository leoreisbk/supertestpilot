package co.work.testpilot

import co.work.testpilot.runtime.Instruction
import co.work.testpilot.runtime.Runner
import co.work.testpilot.throwables.TestAutomationException

class TestActorAndroid : TestActor<AppUISnapshotAndroid, TestableAppAndroid> {
    override suspend fun performInstruction(
        runner: Runner,
        app: TestableAppAndroid,
        instruction: Instruction.Actionable,
        uiSnapshot: AppUISnapshotAndroid,
    ) {
        when (instruction) {
            is Instruction.Type -> {
                val element = uiSnapshot.getAndroidElementById(instruction.id) ?: throw TestAutomationException.ElementNotFound(instruction.id)
                // TODO
            }
            is Instruction.Tap -> {
                val element = uiSnapshot.getAndroidElementById(instruction.id) ?: throw TestAutomationException.ElementNotFound(instruction.id)
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

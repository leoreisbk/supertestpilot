package co.work.testpilot

import co.work.testpilot.runtime.ElementType
import co.work.testpilot.runtime.Instruction
import co.work.testpilot.runtime.Runner
import co.work.testpilot.throwables.TestAutomationException

class TestActorAndroid : TestActor<AppUISnapshotAndroid, TestableAppAndroid> {
    override suspend fun performInstruction(
        runner: Runner,
        app: TestableAppAndroid,
        instruction: Instruction.Actionable,
        uiSnapshot: AppUISnapshotAndroid
    ) {
        when (instruction) {
            is Instruction.Type -> {
                val element = uiSnapshot.getAndroidElementById(instruction.id) ?: throw TestAutomationException.ElementNotFound.WithId(instruction.id)
                element.text = instruction.text
            }
            is Instruction.Tap -> {
                val element = uiSnapshot.getAndroidElementById(instruction.id) ?: throw TestAutomationException.ElementNotFound.WithId(instruction.id)
                element.click()
            }
            is Instruction.ScrollUp -> {
                val displayHeight = app.device.displayHeight
                val aFifthScreenHeight = (displayHeight * 0.2f).toInt()
                app.device.swipe(0, aFifthScreenHeight, 0, displayHeight - aFifthScreenHeight, 100)
            }
            is Instruction.ScrollDown -> {
                val displayHeight = app.device.displayHeight
                val aFifthScreenHeight = (displayHeight * 0.2f).toInt()
                app.device.swipe(0, displayHeight - aFifthScreenHeight, 0, aFifthScreenHeight, 100)
            }
            is Instruction.GoBack -> {
                app.device.pressBack()
            }
        }
        app.device.waitForWindowUpdate(app.packageName, 5000)
    }

    override suspend fun findAndEnsureElementVisibleAndHittable(
        uiSnapshot: AppUISnapshotAndroid,
        type: ElementType,
        label: String,
        app: TestableAppAndroid
    ) {
        TODO("Not yet implemented")
    }
}

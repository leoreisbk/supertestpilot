package co.work.testpilot

import co.work.testpilot.extensions.getElement
import co.work.testpilot.extensions.waitForExistenceIfNecessary
import co.work.testpilot.runtime.Instruction
import co.work.testpilot.runtime.Runner
import co.work.testpilot.throwables.TestAutomationException
import kotlinx.coroutines.delay
import platform.XCTest.*
import kotlin.math.roundToLong

class TestActorIOS(val testCase: XCTestCase) : TestActor<AppUISnapshotIOS, TestableAppIOS> {
    override suspend fun performInstruction(
        runner: Runner,
        app: TestableAppIOS,
        instruction: Instruction.Actionable,
        uiSnapshot: AppUISnapshotIOS,
    ) {
        val xcApp = app.xcApp
        when (instruction) {
            is Instruction.Type -> {
                val match = testCase.getElement(
                    runner = runner,
                    app = xcApp,
                    type = instruction.type,
                    label = instruction.label,
                )
                match.waitForExistenceIfNecessary(timeoutSeconds = 10.0)
                match.tap()
                match.typeText(instruction.text)
            }
            is Instruction.Tap -> {
                val match = testCase.getElement(
                    runner = runner,
                    app = xcApp,
                    type = instruction.type,
                    label = instruction.label,
                )
                match.waitForExistenceIfNecessary(timeoutSeconds = 10.0)
                match.tap()
            }
            is Instruction.ScrollUp -> xcApp.swipeDownWithVelocity(XCUIGestureVelocitySlow)
            is Instruction.ScrollDown -> xcApp.swipeUpWithVelocity(XCUIGestureVelocitySlow)
            is Instruction.GoBack -> {
                val match = xcApp.navigationBars.buttons.elementBoundByIndex(0)
                match.tap()
            }
        }
    }
}

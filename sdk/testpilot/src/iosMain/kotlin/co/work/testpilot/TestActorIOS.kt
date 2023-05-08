package co.work.testpilot

import co.work.testpilot.extensions.findIn
import co.work.testpilot.extensions.toXCUIElementType
import co.work.testpilot.extensions.waitForElementToBecomeVisible
import co.work.testpilot.extensions.waitForExistenceIfNecessary
import co.work.testpilot.runtime.ElementType
import co.work.testpilot.runtime.Instruction
import co.work.testpilot.runtime.Runner
import co.work.testpilot.throwables.TestAutomationException
import platform.XCTest.*

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
                val element = uiSnapshot.getXcElementById(instruction.id)
                    ?.findIn(app.xcApp)
                    ?: throw TestAutomationException.ElementNotFound.WithId(instruction.id)

                element.waitForExistenceIfNecessary(timeoutSeconds = 10.0)
                element.tap()
                element.typeText(instruction.text)
            }
            is Instruction.Tap -> {
                val element = uiSnapshot.getXcElementById(instruction.id)
                    ?.findIn(app.xcApp)
                    ?: throw TestAutomationException.ElementNotFound.WithId(instruction.id)

                element.waitForExistenceIfNecessary(timeoutSeconds = 10.0)
                element.tap()
            }
            is Instruction.ScrollUp -> xcApp.swipeDownWithVelocity(XCUIGestureVelocitySlow)
            is Instruction.ScrollDown -> xcApp.swipeUpWithVelocity(XCUIGestureVelocitySlow)
            is Instruction.GoBack -> {
                val match = xcApp.navigationBars.buttons.elementBoundByIndex(0)
                match.tap()
            }
        }
    }

    override suspend fun findAndEnsureElementVisibleAndHittable(
        uiSnapshot: AppUISnapshotIOS,
        type: ElementType,
        label: String,
        app: TestableAppIOS
    ) {
        val matchingElement = uiSnapshot.firstXcElementOrNull(
            type = type.toXCUIElementType(),
            label = label,
        ) ?: throw TestAutomationException.ElementNotFound.WithLabel(label)

        val isElementVisible = matchingElement.findIn(app.xcApp)
            ?.waitForElementToBecomeVisible(timeoutSeconds = 10.0)
            ?: false

        if (!isElementVisible) {
            throw TestAutomationException.ElementNotFound.WithLabel(label)
        }

        Logging.info("Element of type ($type) and label ($label) is visible and hittable")
    }
}

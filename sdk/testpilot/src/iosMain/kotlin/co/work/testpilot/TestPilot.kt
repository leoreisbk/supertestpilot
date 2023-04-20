package co.work.testpilot

import co.work.testpilot.extensions.elements
import co.work.testpilot.extensions.findIn
import co.work.testpilot.extensions.waitForExistenceIfNecessary
import co.work.testpilot.runtime.Config
import co.work.testpilot.runtime.Instruction
import co.work.testpilot.runtime.Runner
import co.work.testpilot.throwables.ConfigurationException
import co.work.testpilot.throwables.TestAutomationException
import co.work.testpilot.utils.suspendTryOrNull
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import platform.XCTest.*
import kotlin.math.roundToLong

object TestPilot {
    init {
        Logging.start()
    }

    // TODO: config default to empty object
    @Throws(
        TestAutomationException::class,
        ConfigurationException::class,
        CancellationException::class,
        Exception::class
    )
    suspend fun automate(
        test: XCTestCase,
        config: Config,
        objective: String,
        bundleId: String? = null,
    ) {
        val runner = Runner(config)

        val app = if (bundleId != null) {
            XCUIApplication(bundleId)
        } else {
            XCUIApplication()
        }

        app.launch()

        for (stepIndex in 0 until config.maxSteps) {
            println("RUNNING OBJECTIVE: $objective")

            val elementMap = app.elements
            val elementList = elementMap.values.map { it.second }

            val instruction = try {
                runner.getInstruction(objective, elementList)
            } catch (err: Throwable) {
                throw TestAutomationException.CompletionRequestFailed(err)
            }

            Logging.info(" ↳ ${instruction.description}")

            // Execute the instruction
            when (instruction) {
                is Instruction.Assert -> {
                    if (instruction.answer != instruction.expected) {
                        throw TestAutomationException.AssertionFailed(
                            value = instruction.answer,
                            expected = instruction.expected,
                            description = instruction.description,
                        )
                    }
                }
                is Instruction.Type -> {
                    val element = elementMap[instruction.id]?.first?.findIn(app) ?: throw TestAutomationException.ElementNotFound(instruction.id)
                    element.apply {
                        waitForExistenceIfNecessary(timeoutSeconds = 10.0)
                        tap()
                        typeText(instruction.text)
                    }
                }
                is Instruction.Tap -> {
                    val element = elementMap[instruction.id]?.first?.findIn(app) ?: throw TestAutomationException.ElementNotFound(instruction.id)
                    element.apply {
                        waitForExistenceIfNecessary(timeoutSeconds = 10.0)
                        tap()
                    }
                }
                is Instruction.ScrollUp -> app.swipeDownWithVelocity(XCUIGestureVelocitySlow)
                is Instruction.ScrollDown -> app.swipeUpWithVelocity(XCUIGestureVelocitySlow)
                is Instruction.GoBack -> {
                    val match = app.navigationBars.buttons.elementBoundByIndex(0)
                    match.tap()
                }
                is Instruction.Wait -> {
                    delay((instruction.seconds * 1000).roundToLong())
                }
                is Instruction.Done -> return
            }
        }

        throw TestAutomationException.MaxStepsExceeded(config.maxSteps)
    }
}

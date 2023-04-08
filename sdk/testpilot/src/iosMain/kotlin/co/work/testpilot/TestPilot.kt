package co.work.testpilot

import co.work.testpilot.extensions.getElement
import co.work.testpilot.extensions.simplifyUI
import co.work.testpilot.extensions.waitForExistenceIfNecessary
import co.work.testpilot.throwables.TestAutomationException
import co.work.testpilot.utils.suspendTryOrNull
import co.work.testpilot.utils.tryOrNull
import kotlinx.coroutines.delay
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import platform.XCTest.*
import kotlin.math.roundToLong

object TestPilot {
    // TODO: config default to empty object
    suspend fun automate(test: XCTestCase, config: Config, objective: String, bundleId: String? = null) {
        val runner = Runner(config)

        val app = if (bundleId != null) {
            XCUIApplication(bundleId)
        } else {
            XCUIApplication()
        }

        app.launch()
        var lastCommand: String? = null
        val jsonDecoder = Json { ignoreUnknownKeys = true }

        for (stepIndex in 0 until config.maxSteps) {
            val jsonCommand = suspendTryOrNull {
                runner.getCompletionResponse(
                    app.debugDescription?.simplifyUI() ?: "",
                    last = lastCommand,
                    objective = objective,
                )
            } ?: throw TestAutomationException.EmptyResponse()

            // Parse the response
            lastCommand = jsonCommand
            val instruction = jsonDecoder.decodeFromString<Instruction>(jsonCommand)
            // TODO Logging.info(" ↳ \(instruction.description)")

            // Execute the instruction
            when (instruction) {
                is Instruction.Assert -> {
                    // FIXME XCTAssertEqual(instruction.answer, instruction.expected, instruction.description)
                    if (instruction.answer != instruction.expected) {
                        throw TestAutomationException.AssertionFailed(
                            value = instruction.answer,
                            expected = instruction.expected,
                            description = instruction.description,
                        )
                    }
                }
                is Instruction.Type -> {
                    val match = test.getElement(
                        runner = runner,
                        app = app,
                        type = instruction.type,
                        label = instruction.label,
                    )
                    match.waitForExistenceIfNecessary(timeoutSeconds = 10.0)
                    match.tap()
                    match.typeText(instruction.text)
                }
                is Instruction.Tap -> {
                    val match = test.getElement(
                        runner = runner,
                        app = app,
                        type = instruction.type,
                        label = instruction.label,
                    )
                    match.waitForExistenceIfNecessary(timeoutSeconds = 10.0)
                    match.tap()
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

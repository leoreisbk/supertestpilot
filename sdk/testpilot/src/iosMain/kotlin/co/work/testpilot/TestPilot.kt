package co.work.testpilot

import co.work.testpilot.extensions.getElement
import co.work.testpilot.extensions.simplifyUI
import co.work.testpilot.extensions.waitForExistenceIfNecessary
import co.work.testpilot.throwables.ConfigurationException
import co.work.testpilot.throwables.TestAutomationException
import co.work.testpilot.utils.suspendTryOrNull
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import platform.XCTest.*
import kotlin.math.roundToLong

object TestPilot {
    init {
        Logging.start()
    }

    // TODO: config default to empty object
    @Throws(TestAutomationException::class, ConfigurationException::class, CancellationException::class, Exception::class)
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
            val jsonCommand = try {
                runner.getCompletionResponse(
                    app.debugDescription?.simplifyUI() ?: "",
                    last = lastCommand,
                    objective = objective,
                )
            } catch (err: Throwable) {
                throw TestAutomationException.CompletionRequestFailed(err)
            }
            if (jsonCommand.isNullOrEmpty()) {
                throw TestAutomationException.EmptyResponse()
            }

            // Parse the response
            lastCommand = jsonCommand
            val instruction = jsonDecoder.decodeFromString<Instruction>(jsonCommand)
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

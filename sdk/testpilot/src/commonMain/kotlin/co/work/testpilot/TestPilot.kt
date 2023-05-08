package co.work.testpilot

import co.work.testpilot.runtime.Config
import co.work.testpilot.runtime.Instruction
import co.work.testpilot.runtime.Runner
import co.work.testpilot.throwables.TestAutomationException
import co.work.testpilot.utils.suspendTryOrNull
import kotlinx.coroutines.delay
import kotlin.math.roundToLong

object TestPilot {
    init {
        Logging.start()
    }

    suspend fun <Snapshot: AppUISnapshot, App: TestableApp<Snapshot>> automate(
        app: App,
        actor: TestActor<Snapshot, App>,
        config: Config,
        objective: String,
    ) {
        val runner = Runner(config)

        app.launch()

        for (stepIndex in 0 until config.maxSteps) {
            println("RUNNING OBJECTIVE: $objective")

            val uiSnapshot = app.snapshot()

            val instruction = try {
                runner.getInstruction(objective, uiSnapshot)
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
                is Instruction.Wait -> {
                    delay((instruction.seconds * 1000).roundToLong())
                }
                is Instruction.Done -> return
                is Instruction.Actionable -> actor.performInstruction(
                    runner = runner,
                    app = app,
                    instruction = instruction,
                    uiSnapshot = uiSnapshot,
                )
                is Instruction.Check -> {
                    try {
                        // Try to find an element that matches the exact parameters.
                        actor.findAndEnsureElementVisibleAndHittable(
                            uiSnapshot = uiSnapshot,
                            type = instruction.type,
                            label = instruction.label,
                            app = app,
                        )
                    } catch (err: Throwable) {
                        // We couldn't find an element that matches the exact parameters. Use embeddings to find the most appropriate
                        // element.
                        val bestMatchingLabel = suspendTryOrNull {
                            runner.searchEmbeddings(
                                items = uiSnapshot.allElements.map { it.label },
                                query = instruction.label,
                                n = 1,
                            ).firstOrNull()
                        } ?: throw TestAutomationException.ElementNotFound.WithLabel(instruction.label)

                        actor.findAndEnsureElementVisibleAndHittable(
                            uiSnapshot = uiSnapshot,
                            type = instruction.type,
                            label = bestMatchingLabel,
                            app = app,
                        )
                    }
                }
            }
        }

        throw TestAutomationException.MaxStepsExceeded(config.maxSteps)
    }
}

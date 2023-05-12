package co.work.testpilot

import co.work.testpilot.runtime.Config
import co.work.testpilot.runtime.Instruction
import co.work.testpilot.runtime.Runner
import co.work.testpilot.throwables.TestAutomationException
import co.work.testpilot.utils.suspendTryOrNull
import kotlinx.coroutines.delay
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.math.roundToLong

object TestPilot {
    init {
        Logging.start()
    }

    private suspend fun getPersistableInstruction(
        persistenceManager: PersistenceManager,
        shouldRecordSteps: Boolean,
        stepIndex: Int,
        objective: String,
        uiSnapshot: AppUISnapshot,
        runner: Runner,
    ): Instruction {
        val serializer = Json { ignoreUnknownKeys = true }

        // Try retrieving a recorded step first
        val recordedInstruction = if (!shouldRecordSteps) {
            persistenceManager.getStep(stepIndex)
        } else null

        return if (recordedInstruction != null) {
            // If there is a recorded step at this position, return it.
            recordedInstruction
        } else {
            // If we don't have a recorded step, use inference
            val result = try {
                runner.getInstruction(objective, uiSnapshot)
            } catch (err: Throwable) {
                throw TestAutomationException.CompletionRequestFailed(err)
            }

            if (shouldRecordSteps) {
                persistenceManager.recordStep(result)
            }
            serializer.decodeFromString(result)
        }
    }

    suspend fun <Snapshot: AppUISnapshot, App: TestableApp<Snapshot>> automate(
        app: App,
        actor: TestActor<Snapshot, App>,
        config: Config,
        objective: String,
        persistenceManager: PersistenceManager,
        fallbackToAPIOnErrors: Boolean = true,
    ) {
        if (!persistenceManager.isEmpty()) {
            try {
                // If we have pre-recorded steps, try running them first
                runSession(
                    app = app,
                    actor = actor,
                    config = config,
                    objective = objective,
                    persistenceManager = persistenceManager,
                    shouldRecordSteps = false,
                )
                // If pre-recorded session succeeds, no need to run another session.
                return
            } catch (err: Throwable) {
                if (!fallbackToAPIOnErrors) {
                    throw err
                }
                // If pre-recorded steps fail, clear it before trying to run a fresh session
                persistenceManager.clear()
            }
        }

        runSession(
            app = app,
            actor = actor,
            config = config,
            objective = objective,
            persistenceManager = persistenceManager,
            shouldRecordSteps = true,
        )
    }

    suspend fun <Snapshot: AppUISnapshot, App: TestableApp<Snapshot>> runSession(
        app: App,
        actor: TestActor<Snapshot, App>,
        config: Config,
        objective: String,
        persistenceManager: PersistenceManager,
        shouldRecordSteps: Boolean,
    ) {
        if (shouldRecordSteps) {
            Logging.info("** Recording Steps **")
        }
        val runner = Runner(config)

        app.launch()

        for (stepIndex in 0 until config.maxSteps) {
            println("RUNNING OBJECTIVE: $objective")

            val uiSnapshot = app.snapshot()

            val instruction = getPersistableInstruction(
                persistenceManager = persistenceManager,
                shouldRecordSteps = shouldRecordSteps,
                stepIndex = stepIndex,
                objective = objective,
                uiSnapshot = uiSnapshot,
                runner = runner,
            )
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
                is Instruction.Done -> {
                    if (shouldRecordSteps) {
                        persistenceManager.persistSteps()
                    }
                    return
                }
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

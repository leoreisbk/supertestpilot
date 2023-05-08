package co.work.testpilot.runtime

import co.work.testpilot.AppUISnapshot
import co.work.testpilot.openai.OpenAIModel
import co.work.testpilot.runtime.prompts.InstructPrompt
import co.work.testpilot.runtime.prompts.InstructPromptInput
import co.work.testpilot.runtime.prompts.SimplifyPrompt
import co.work.testpilot.runtime.prompts.SimplifyPromptInput
import co.work.testpilot.throwables.TestAutomationException
import com.aallam.openai.api.logging.LogLevel
import com.aallam.openai.client.OpenAI
import com.aallam.openai.client.OpenAIConfig
import com.aallam.openai.client.OpenAIHost
import kotlin.coroutines.cancellation.CancellationException

class Runner(private val config: Config) {
    private val aiClient = OpenAI(config = OpenAIConfig(
        token = config.apiKey,
        logLevel = LogLevel.None
    ))

    private val simplifyPrompt = SimplifyPrompt(aiClient, config)
    private val instructPrompt = InstructPrompt(aiClient, config)
    private var lastInstruction: Instruction? = null

    @Throws(TestAutomationException::class, CancellationException::class)
    suspend fun getInstruction(objective: String, uiSnapshot: AppUISnapshot): Instruction {
        val simplifiedUI = simplifyPrompt(SimplifyPromptInput(objective, uiSnapshot.toPromptString()))
        val instruction = instructPrompt(InstructPromptInput(objective, simplifiedUI, lastInstruction))
        lastInstruction = instruction
        return instruction
    }
}

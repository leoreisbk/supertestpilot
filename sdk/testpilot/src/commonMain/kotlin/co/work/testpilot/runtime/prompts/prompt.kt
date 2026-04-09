package co.work.testpilot.runtime.prompts

import co.work.testpilot.ai.AIClient
import co.work.testpilot.runtime.Config

interface Prompt<I, O> {
    suspend fun run(input: I): O
    suspend operator fun invoke(input: I) = run(input)
}

abstract class AIPrompt<I, O>(
    protected val client: AIClient,
    protected val config: Config,
) : Prompt<I, O>

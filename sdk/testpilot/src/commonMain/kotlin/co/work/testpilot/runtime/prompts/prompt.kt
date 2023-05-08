package co.work.testpilot.runtime.prompts

import co.work.testpilot.Logging
import co.work.testpilot.runtime.Config
import com.aallam.openai.api.BetaOpenAI
import com.aallam.openai.api.chat.ChatCompletion
import com.aallam.openai.api.chat.ChatCompletionRequest
import com.aallam.openai.client.OpenAI

interface Prompt<I, O> {
    suspend fun run(input: I): O
    suspend operator fun invoke(input: I) = run(input)
}

@OptIn(BetaOpenAI::class)
abstract class OpenAIPrompt<I, O>(protected val client: OpenAI, protected val config: Config): Prompt<I, O> {
    protected companion object {
        suspend fun OpenAI.testPilotChatCompletion(request: ChatCompletionRequest): ChatCompletion {
            val requestLogString = "=====\nCHAT REQUEST:\n=====\n" + request.debugString
            Logging.info(requestLogString)
            val response = chatCompletion(request)
            response.firstCompletionContent?.let {
                Logging.info("=====\nCHAT RESPONSE:\n=====\n$it")
            }
            return response
        }

        val ChatCompletion.firstCompletionContent: String?
            get() = choices.first().message?.content

        private val ChatCompletionRequest.debugString: String
            get() = messages.joinToString("\n") { "Message(${it.role.role}): ${it.content}" }
    }
}
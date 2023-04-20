package co.work.testpilot.runtime.prompts

import co.work.testpilot.Logging
import com.aallam.openai.api.BetaOpenAI
import com.aallam.openai.api.chat.ChatCompletion
import com.aallam.openai.api.chat.ChatCompletionRequest
import com.aallam.openai.client.OpenAI

interface Prompt<I, O> {
    suspend fun run(input: I): O
    suspend operator fun invoke(input: I) = run(input)
}

@OptIn(BetaOpenAI::class)
abstract class OpenAIPrompt<I, O>(protected val client: OpenAI): Prompt<I, O> {
    protected enum class OpenAIModel(val idString: String) {
        GPT3_TextEmbeddingAda002("text-embedding-ada-002"),
        GPT3_TextDavinci003("text-davinci-003"),
        GPT3_5_Turbo(idString = "gpt-3.5-turbo"),
        GPT3_5_Turbo_0301(idString = "gpt-3.5-turbo-0301"),
        GPT4("gpt-4"),
        GPT4_0314("gpt-4-0314"),
    }

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
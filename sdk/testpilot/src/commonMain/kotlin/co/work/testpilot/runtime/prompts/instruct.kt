@file:OptIn(BetaOpenAI::class)

package co.work.testpilot.runtime.prompts

import co.work.testpilot.runtime.Config
import co.work.testpilot.openai.OpenAIModel
import co.work.testpilot.runtime.Instruction
import co.work.testpilot.throwables.TestAutomationException
import co.work.testpilot.utils.removeComments
import com.aallam.openai.api.BetaOpenAI
import com.aallam.openai.api.chat.ChatCompletionRequest
import com.aallam.openai.api.chat.ChatMessage
import com.aallam.openai.api.chat.ChatRole
import com.aallam.openai.api.model.ModelId
import com.aallam.openai.client.OpenAI
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

data class InstructPromptInput(val objective: String, val simplifiedUI: String, val lastInstruction: String? = null)

class InstructPrompt(client: OpenAI, config: Config): OpenAIPrompt<InstructPromptInput, String>(client, config) {
    override suspend fun run(input: InstructPromptInput): String {
        val request = ChatCompletionRequest(
            model = ModelId(OpenAIModel.GPT4_0314.idString),
            messages = listOf(
                ChatMessage(ChatRole.System, system(input.objective)),
                ChatMessage(ChatRole.User, uiState(
                    input.simplifiedUI,
                    input.lastInstruction
                )),
            ),
            temperature = config.temperature,
            n = 1,
            maxTokens = config.maxTokens,
        )
        val response = client.testPilotChatCompletion(request)
        val jsonCommand = response.firstCompletionContent ?: throw TestAutomationException.EmptyResponse()
        return jsonCommand
    }

    private companion object {
        val serializer = Json { ignoreUnknownKeys = true }

        fun system(objective: String) = """
        As a mobile app agent, you have an objective and a simplified UI description
        Analyze the UI content and respond with the command which you believe will help achieve your objective
        You should only yield one command
        The UI is highly simplified
        Navigating means tapping an element
        You're also being given the last command you executed in order to assess if you've finished your objective
        Provide a very short string in the "reason" attr with what you're trying to achieve
        Don't try to interact with elements you can't see
        If your command needs a type and a label, use only values on the same line

        You can issue only these commands:
        {"cmd": "tap", id: X, "reason": "REASON"} - Tap on the UI element with integer id X.
        {"cmd": "type", id: X, "text": "TEXT", "reason": "REASON"}  - Type the specified text into the UI element with integer id X.
        {"cmd": "assert", "answer": "ANSWER", "expected": "EXPECTED", "reason": "REASON"} - You've been asked to compare or check a value with what you see. ANSWER should be what you found and EXPECTED the value that was given in the objective. Leave the ANSWER null if you can't find it.
        {"cmd": "scrollDown", "reason": "REASON"} - Scrolls down in the current page
        {"cmd": "scrollUp", "reason": "REASON"} - Scrolls up in the current page
        {"cmd": "goBack", "reason": "REASON"} - Go Back, regardless of the element
        {"cmd": "wait", "seconds": X, "reason": "REASON"} - Wait or sleep for X seconds. X is a Double
        {"cmd": "done", "reason": "REASON"} - You think you've fulfilled your objective and there's nothing more to do
        {"cmd": "check", "type": "E", "label": "X", "reason": "REASON"} - check if the current UI element of type "E" exists with label "X"

        EXAMPLE:
        ===
        OBJECTIVE: Page should be named Sales
        LAST: {"cmd": "tap", "id": 12, "reason": "Instructed by the objective"}
        UI:
        NavigationBar, id: 0, label: 'Sales'
        StaticText, id: 1, label: 'Sale'
        ---
        YOU:
        {"cmd": "assert", "answer": "Sales", "expected": "Sales", "reason": "Value found on the NavigationBar"}
        ===

        EXAMPLE:
        ===
        OBJECTIVE: Go to Profile
        LAST: null
        UI:
        TabBar, id: 0, label: 'Tab Bar'
        Button, id: 1, label: 'Profile Tab'
        StaticText, id: 2, label: 'Profile'
        Button, id: 3, label: 'Sales', Selected
        ---
        YOU:
        {"cmd": "tap", "id": 1, "reason": "Going to the Profile tab"}
        ===

        EXAMPLE:
        OBJECTIVE: User statement should be 0
        LAST: {"cmd": "tap", "id": 1, "reason": "Going to the Profile tab"}
        UI:
        StaticText, id: 0, label: 'useremail@domain.co'
        Other, id: 1, label: 'Statement', value: 750,762
        StaticText, id: 2, label: '1 Infinite Loop'
        ---
        YOU:
        {"cmd": "assert", "answer": "750,762", "expected": "0", "reason": "Value found on an element labeled 'Statement'"}
        ===

        Your objective is listed below.
        ===
        OBJECTIVE: $objective
        """
            .trimIndent()
            .removeComments()

        fun uiState(simplifiedUI: String, last: String?) = """
        LAST: ${last ?: "null"}
        UI:
        $simplifiedUI
        ---
        YOU:
        """.trimIndent()
    }
}
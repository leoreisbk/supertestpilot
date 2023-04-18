package co.work.testpilot.throwables

import com.aallam.openai.api.exception.OpenAIAPIException
import com.aallam.openai.api.exception.OpenAIHttpException

sealed class TestAutomationException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class EmptyResponse : TestAutomationException("OpenAI returned empty response")
    class MaxStepsExceeded(maxSteps: Int) : TestAutomationException("Maximum number of steps exceeded ($maxSteps)")
    class ElementNotFound(label: String) : TestAutomationException("Element not found ($label)")
    class AssertionFailed(value: String?, expected: String?, description: String? = null) : TestAutomationException(
        "Assertion ${description?.let { "'$it'" } ?: ""} failed (value: $value, expected: $expected"
    )
    class InvalidCommand(cmd: String?) : TestAutomationException("Invalid command '$cmd'")
    class CompletionRequestFailed(
        cause: Throwable,
        message: String? = when (cause) {
            is OpenAIAPIException -> cause.error.detail?.message
            is OpenAIHttpException -> cause.cause?.message
            else -> cause.message
        } ?: cause.cause?.message
    ) : TestAutomationException("The completion request failed (${message})", cause)
}

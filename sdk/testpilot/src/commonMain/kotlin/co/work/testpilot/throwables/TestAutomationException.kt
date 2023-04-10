package co.work.testpilot.throwables

sealed class TestAutomationException(message: String) : Exception(message) {
    class EmptyResponse : TestAutomationException("OpenAI returned empty response")
    class MaxStepsExceeded(maxSteps: Int) : TestAutomationException("Maximum number of steps exceeded ($maxSteps)")
    class ElementNotFound(label: String) : TestAutomationException("Element not found ($label)")
    class AssertionFailed(value: String?, expected: String?, description: String? = null) : TestAutomationException(
        "Assertion ${description?.let { "'$it'" } ?: ""} failed (value: $value, expected: $expected"
    )
    class InvalidCommand(cmd: String?) : TestAutomationException("Invalid command '$cmd'")
}

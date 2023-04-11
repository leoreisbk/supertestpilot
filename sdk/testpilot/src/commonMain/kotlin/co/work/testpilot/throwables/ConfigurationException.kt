package co.work.testpilot.throwables

sealed class ConfigurationException(message: String) : Exception(message) {
    class ApiKeyRequired : ConfigurationException("You must provide an API Key with a Config, or as an OPEN_AI_KEY env var")
}

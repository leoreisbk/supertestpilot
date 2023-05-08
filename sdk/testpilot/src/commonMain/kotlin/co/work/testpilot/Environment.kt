package co.work.testpilot

import io.ktor.http.*

class Environment {
    companion object {
        val apiKey = env("OPEN_AI_KEY")
        val openAIHost = env("OPEN_AI_HOST")
        val openAIOrg = env("OPEN_AI_ORG")
        val openAIHeaders = env("OPEN_AI_HEADERS")
        val wsReceiver = env("WS_RECEIVER")
        val wsReceiverUrl = env("WS_SERVER")
    }
}

val Environment.Companion.parsedHeaders: Map<String, String> get() {
    return openAIHeaders
        ?.split(Regex("(?<!\\\\);")) // This regex allows values to be escaped if they contain a semicolon.
        ?.fold(emptyMap()) { result, item ->
            val colonIndex = item.indexOf(":")
            val key = item.subSequence(0, colonIndex).toString()
            val value = item.subSequence(colonIndex + 1, item.length).toString()

            result + mapOf(key to value)
        }
        ?: emptyMap()
}
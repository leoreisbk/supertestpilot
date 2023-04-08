package co.work.testpilot

import io.ktor.http.*

class Environment {
    companion object {
        val apiKey = env("OPEN_AI_KEY")
        val wsReceiver = env("WS_RECEIVER")
        val wsReceiverUrl = env("WS_SERVER")?.let { Url(it) }
    }
}

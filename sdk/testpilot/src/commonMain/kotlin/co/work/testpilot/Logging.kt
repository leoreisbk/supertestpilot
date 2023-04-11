package co.work.testpilot

import io.ktor.client.*
import io.ktor.client.plugins.websocket.*
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.Serializable

@Serializable
data class LoggingMessage(val rcv: String, val msg: String)

object Logging {
    private val outgoingFlow = MutableSharedFlow<LoggingMessage>()
    private val receiver = Environment.wsReceiver
    private val scope = CoroutineScope(Dispatchers.Default)

    internal fun start() {
        val url = Environment.wsReceiverUrl
        if (url == null) {
            println("Invalid websocket logging server URL defined on environment variable WS_SERVER")
            return
        }
        if (receiver == null) {
            println("Websocket logging receiver not found on environment variable WS_RECEIVER")
            return
        }

        val client = HttpClient {
            install(WebSockets)
        }
        scope.launch {
            client.webSocket(
                request = { },
                urlString = url,
            ) {
                outgoingFlow.collect { message ->
                    outgoing.send(Frame.Text(Json.encodeToString(message)))
                }
            }
        }
    }

    fun info(msg: String) {
        if (receiver != null) {
            scope.launch {
                try {
                    outgoingFlow.emit(LoggingMessage(rcv = receiver, msg = msg))
                } catch (err: Throwable) {
                    println("Couldn't log message: ${err.message}")
                }
            }
        } else {
            println("Message not sent to logging server - $msg")
        }
    }
}

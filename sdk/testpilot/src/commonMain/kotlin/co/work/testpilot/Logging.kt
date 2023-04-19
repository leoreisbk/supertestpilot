package co.work.testpilot

import io.ktor.client.*
import io.ktor.client.plugins.websocket.*
import io.ktor.utils.io.core.*
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.channels.consumeEach
import kotlinx.coroutines.flow.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.Serializable

private const val pingIntervalSeconds = 30
private const val pingTimeoutSeconds = 10

@Serializable
data class LoggingMessage(val rcv: String, val msg: String)

object Logging {
    private val outgoingChannel = Channel<LoggingMessage>(
        capacity = 50, // Max number of log entries that will be buffered if the socket is not connected
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
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

        scope.launch {
            val client = HttpClient {
                install(WebSockets)
            }
            try {
                // Connect to the ws server
                client.webSocket(
                    request = { },
                    urlString = url,
                ) {
                    pingIntervalMillis = pingIntervalSeconds * 1000L
                    timeoutMillis = pingTimeoutSeconds * 1000L
                    val outgoingJob = launch {
                        outgoingChannel.consumeEach { message ->
                            outgoing.send(Frame.Text(Json.encodeToString(message)))
                        }
                    }
                    val incomingJob = startReceiveJob(incoming)
                    listOf(outgoingJob, incomingJob).joinAll()
                }
            } catch (err: Throwable) {
                println("Could not connect to logging server: $err")
            }
        }
    }

    private fun CoroutineScope.startReceiveJob(channel: ReceiveChannel<Frame>): Job {
        // Receiving messages
        return launch {
            channel.receiveAsFlow()
                .catch { err ->
                    println(err)
                }
                .collect { result ->
                    val content = String(result.data)
                    println(content)
                }
        }
    }

    fun info(msg: String) {
        if (receiver != null) {
            scope.launch {
                try {
                    outgoingChannel.send(LoggingMessage(rcv = receiver, msg = msg))
                } catch (err: Throwable) {
                    println("Couldn't log message: ${err.message}")
                }
            }
        } else {
            println("Message not sent to logging server - $msg")
        }
    }
}

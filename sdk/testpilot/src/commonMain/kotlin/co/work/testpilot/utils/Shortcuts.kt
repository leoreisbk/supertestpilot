package co.work.testpilot.utils

suspend fun <T> suspendTryOrNull(callback: suspend () -> T): T? {
    return try {
        callback()
    } catch (err: Throwable) {
        null
    }
}

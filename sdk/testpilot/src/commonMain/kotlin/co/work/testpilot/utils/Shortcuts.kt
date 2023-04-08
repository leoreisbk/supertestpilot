package co.work.testpilot.utils

fun <T> tryOrNull(callback: () -> T): T? {
    return try {
        callback()
    } catch (err: Throwable) {
        null
    }
}

suspend fun <T> suspendTryOrNull(callback: suspend () -> T): T? {
    return try {
        callback()
    } catch (err: Throwable) {
        null
    }
}

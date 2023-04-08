package co.work.testpilot.utils

fun String.removeComments(): String {
    return try {
        val regex = Regex("//.*")
        regex.replace(this, "")
    } catch (err: Throwable) {
        this
    }
}

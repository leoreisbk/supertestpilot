package co.work.testpilot

actual fun env(key: String): String? = System.getenv(key)

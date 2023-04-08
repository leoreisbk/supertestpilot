package co.work.testpilot

interface Platform {
    val name: String
}

expect fun getPlatform(): Platform
expect fun env(key: String): String?

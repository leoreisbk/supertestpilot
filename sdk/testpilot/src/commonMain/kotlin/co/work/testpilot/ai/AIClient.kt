package co.work.testpilot.ai

/** Detects image MIME type from magic bytes. Defaults to "image/jpeg" (primary iOS output path). */
internal fun ByteArray.imageMimeType(): String =
    if (size >= 2 && this[0] == 0xFF.toByte() && this[1] == 0xD8.toByte()) "image/jpeg" else "image/png"

interface AIClient {
    suspend fun chatCompletion(
        messages: List<ChatMessage>,
        maxTokens: Int,
        temperature: Double,
        imageBytes: ByteArray? = null,
    ): String
}

data class ChatMessage(val role: String, val content: String) {
    companion object {
        const val ROLE_SYSTEM = "system"
        const val ROLE_USER = "user"
        const val ROLE_ASSISTANT = "assistant"
    }
}

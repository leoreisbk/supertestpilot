package co.work.testpilot.ai

import io.github.aakira.napier.Napier
import java.io.File

class CachingAIClientJvm(
    private val delegate: AIClient,
    private val cacheDir: String,
    private val onCacheHit: (() -> Unit)? = null,
) : AIClient {

    override suspend fun chatCompletion(
        messages: List<ChatMessage>,
        maxTokens: Int,
        temperature: Double,
        imageBytes: ByteArray?,
    ): String {
        val userPrompt = messages.lastOrNull { it.role == ChatMessage.ROLE_USER }?.content ?: ""
        val key = cacheKey(imageBytes, userPrompt)
        val cacheFile = File("$cacheDir/$key.json")

        if (cacheFile.exists()) {
            try {
                val cached = cacheFile.readText()
                Napier.i("CachingAIClientJvm: cache hit [$key]")
                onCacheHit?.invoke()
                return cached
            } catch (e: Exception) {
                System.err.println("TestPilot: cache read error: ${e.message}")
            }
        }

        val response = delegate.chatCompletion(messages, maxTokens, temperature, imageBytes)

        try {
            File(cacheDir).mkdirs()
            cacheFile.writeText(response)
        } catch (e: Exception) {
            System.err.println("TestPilot: cache write error: ${e.message}")
        }

        return response
    }

    // 64-bit FNV-1a over sampled screenshot bytes + full prompt text.
    // Samples every 200th screenshot byte to keep hashing fast on large PNGs.
    // Matches the algorithm in CachingAIClient (iosMain).
    private fun cacheKey(imageBytes: ByteArray?, userPrompt: String): String {
        var h = 14695981039346656037UL
        imageBytes?.let { bytes ->
            var i = 0
            while (i < bytes.size) {
                h = h xor bytes[i].toUByte().toULong()
                h *= 1099511628211UL
                i += 200
            }
        }
        for (c in userPrompt) {
            h = h xor c.code.toULong()
            h *= 1099511628211UL
        }
        return h.toString(16).padStart(16, '0')
    }
}

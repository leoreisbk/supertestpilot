package co.work.testpilot.ai

import co.work.testpilot.Logging
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.readBytes
import platform.Foundation.NSData
import platform.Foundation.NSFileManager
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.dataUsingEncoding
import platform.Foundation.writeToFile

class CachingAIClient(
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
        val cachePath = "$cacheDir/$key.json"

        val cached = readFile(cachePath)
        if (cached != null) {
            Logging.info("CachingAIClient: cache hit [$key]")
            onCacheHit?.invoke()
            return cached
        }

        val result = delegate.chatCompletion(messages, maxTokens, temperature, imageBytes)
        writeFile(cachePath, result)
        return result
    }

    // 64-bit FNV-1a over sampled screenshot bytes + full prompt text.
    // Samples every 200th screenshot byte (same interval as Analyst.fingerprint)
    // to keep hashing fast on large PNGs.
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

    @OptIn(ExperimentalForeignApi::class)
    private fun readFile(path: String): String? {
        return try {
            val data = NSData.dataWithContentsOfFile(path) ?: return null
            val bytes = data.bytes ?: return null
            bytes.readBytes(data.length.toInt()).decodeToString()
        } catch (_: Exception) { null }
    }

    @OptIn(ExperimentalForeignApi::class)
    private fun writeFile(path: String, content: String) {
        try {
            NSFileManager.defaultManager.createDirectoryAtPath(
                cacheDir,
                withIntermediateDirectories = true,
                attributes = null,
                error = null,
            )
            val data = (content as NSString).dataUsingEncoding(NSUTF8StringEncoding) ?: return
            data.writeToFile(path = path, atomically = true)
        } catch (_: Exception) {
            Logging.info("CachingAIClient: failed to write cache entry at $path")
        }
    }
}

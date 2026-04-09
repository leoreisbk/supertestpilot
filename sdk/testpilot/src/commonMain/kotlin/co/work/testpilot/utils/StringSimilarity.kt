package co.work.testpilot.utils

import kotlin.math.max
import kotlin.math.min

/**
 * Pure-Kotlin string similarity for fuzzy UI element matching.
 * Used as a fallback when OpenAI embeddings are unavailable (e.g. Anthropic provider).
 *
 * Scoring (0.0–1.0):
 *   1.0  exact match (case-insensitive)
 *   0.9  one string contains the other
 *   0–1  normalized Levenshtein otherwise
 */
object StringSimilarity {

    fun score(a: String, b: String): Double {
        val na = a.trim().lowercase()
        val nb = b.trim().lowercase()
        if (na == nb) return 1.0
        if (na.isEmpty() || nb.isEmpty()) return 0.0
        if (na.contains(nb) || nb.contains(na)) return 0.9
        val distance = levenshtein(na, nb)
        return 1.0 - distance.toDouble() / max(na.length, nb.length)
    }

    /** Returns the top-n items from [candidates] most similar to [query]. */
    fun search(candidates: List<String>, query: String, n: Int): List<String> =
        candidates
            .filter { it.isNotBlank() }
            .map { it to score(it, query) }
            .sortedByDescending { it.second }
            .take(n)
            .map { it.first }

    private fun levenshtein(a: String, b: String): Int {
        val m = a.length
        val n = b.length
        val dp = Array(m + 1) { IntArray(n + 1) }
        for (i in 0..m) dp[i][0] = i
        for (j in 0..n) dp[0][j] = j
        for (i in 1..m) {
            for (j in 1..n) {
                dp[i][j] = if (a[i - 1] == b[j - 1]) {
                    dp[i - 1][j - 1]
                } else {
                    1 + min(dp[i - 1][j], min(dp[i][j - 1], dp[i - 1][j - 1]))
                }
            }
        }
        return dp[m][n]
    }
}

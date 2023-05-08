package co.work.testpilot.utils

import com.aallam.openai.api.embedding.Embedding
import kotlin.math.sqrt

data class EmbeddingElement(
    val embedding: Embedding,
    val text: String
)

data class SearchScore(
    val text: String,
    val score: Double,
)

object EmbeddingUtils {
    fun searchScore(document: List<EmbeddingElement>, query: Embedding, n: Int): List<SearchScore> {
        val result = document
            .map {
                SearchScore(
                    text = it.text,
                    score = cosineSim(it.embedding.embedding, query.embedding)
                )
            }
            .sortedByDescending { it.score }

        return result.take(n)
    }

    fun search(document: List<EmbeddingElement>, query: Embedding, n: Int): List<String> {
        return searchScore(document, query, n)
            .map { it.text }
    }

    /** Cosine similarity **/
    private fun cosineSim(a: List<Double>, b: List<Double>): Double {
        return dot(a, b) / (magnitude(a) * magnitude(b))
    }

    /** Dot Product **/
    private fun dot(a: List<Double>, b: List<Double>): Double {
        var x = 0.0
        for (i in a.indices) {
            x += a[i] * b[i]
        }
        return x
    }

    /** Vector Magnitude **/
    private fun magnitude(a: List<Double>): Double {
        var x = 0.0
        for (element in a) {
            x += element * element
        }
        return sqrt(x)
    }
}

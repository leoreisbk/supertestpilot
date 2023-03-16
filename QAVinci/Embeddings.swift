//
//  Embeddings.swift
//  QAVinci
//
//  Created by Flávio Caetano on 3/15/23.
//

import Foundation
import OpenAIKit

extension Embedding {
    static func searchScore(on document: [(Embedding, String)], query: Embedding, n: Int) -> [(Float, String)] {
        let result = document
            .lazy
            .map { emb, text -> (Float, String) in
                (cosineSim(A: emb.embedding, B: query.embedding), text)
            }
            // descending
            .sorted { $0.0 > $1.0 }

        print(result)

        return Array(result
            .prefix(upTo: n))
    }

    static func search(on document: [(Embedding, String)], query: Embedding, n: Int) -> [String] {
        searchScore(on: document, query: query, n: n)
            .map { $1 }
    }

    /** Cosine similarity **/
    private static func cosineSim(A: [Float], B: [Float]) -> Float {
        return dot(A: A, B: B) / (magnitude(A: A) * magnitude(A: B))
    }

    /** Dot Product **/
    private static func dot(A: [Float], B: [Float]) -> Float {
        var x: Float = 0
        for i in 0...A.count-1 {
            x += A[i] * B[i]
        }
        return x
    }

    /** Vector Magnitude **/
    private static func magnitude(A: [Float]) -> Float {
        var x: Float = 0
        for elt in A {
            x += elt * elt
        }
        return sqrt(x)
    }
}

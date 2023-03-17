//
//  Runner.swift
//  QAVinci
//
//  Created by Flávio Caetano on 3/13/23.
//

import Foundation
import XCTest
import OpenAIKit
import AsyncHTTPClient

class Runner {
    let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
    let aiClient: OpenAIKit.Client
    let config: Config

    init(config: Config) {
        self.config = config
        self.aiClient = OpenAIKit.Client(
            httpClient: httpClient,
            configuration: .init(apiKey: config.apiKey)
        )
    }
}

extension Runner {
    func getCompletionResponse(for ui: String, objective: String) async throws -> String? {
        let response = try await aiClient.completions.create(
            model: Model.GPT3.textDavinci003,
            prompts: [
                Prompts.system(objective: objective) +
                """

                UI:
                \(ui)
                ---
                YOU:
                """
            ],
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            n: 1
        )

        return response.choices[0].text
    }

    func getCompletionSetup(objective: String) async throws -> [String] {
        let response = try await aiClient.completions.create(
            model: Model.GPT3.textDavinci003,
            prompts: [
                Prompts.steps(objective: objective)
            ],
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            n: 1
        )

        return try JSONDecoder().decode([String].self, from: Data(response.choices[0].text.utf8))
    }

    func searchEmbeddings(input: String, query: String, n: Int = 1) async throws -> [String] {
        let texts = input
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        let response = try await aiClient.embeddings.create(input: texts + [query])

        return Embedding.search(
            on: response.data
                .dropLast(1)
                .enumerated()
                .map { idx, elem in
                    (elem, texts[idx])
                },
            query: response.data.last!,
            n: n
        )
    }
}

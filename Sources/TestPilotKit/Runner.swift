//
//  Runner.swift
//  TestPilotKit
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
            configuration: config.openAIConfig
        )
    }
}

extension Runner {
    func getCompletionResponse(for ui: String, last: String?, objective: String) async throws -> String? {
        let response = try await aiClient.chats.create(
            model: Model.GPT4.gpt40314,
            messages: [
                .system(content: Prompts.system(objective: objective)),
                .user(content: """
                LAST: \(last ?? "null")
                UI:
                \(ui)
                ---
                YOU:
                """),
            ],
            temperature: config.temperature,
            n: 1,
            maxTokens: config.maxTokens
        )
        print("=================Objective: \(objective)")
        print("=================Completion Response: \(response.choices[0].message.content)")
        return response.choices[0].message.content
    }

    func splitIntoSteps(objective: String) async throws -> [String] {
        let response = try await aiClient.completions.create(
            model: Model.GPT3.textDavinci003,
            prompts: [
                Prompts.stepsCompletion(objective: objective)
            ],
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            n: 1
        )
        
        print("===========Spliting into steps: \(response.choices)")

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

private extension Chat.Message {
    var content: String {
        switch self {
        case let .user(content: result): return result
        case let .system(content: result): return result
        case let .assistant(content: result): return result
        }
    }
}

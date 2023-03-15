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

    func getRelevantLabel(ui: String, type: String, label: String) async throws -> String {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8082")!)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "type": type,
            "label": label,
            "document": ui,
        ])
        request.setValue(config.apiKey, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard 200..<300 ~= code, let line = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }

        let match = line.firstMatch(of: /label: '(.*?)'($|,)/)!
        return String(match.output.1)
    }
}

//
//  Config.swift
//  TestPilotKit
//
//  Created by Flávio Caetano on 3/13/23.
//

import Foundation

public struct Config {
    let apiKey: String
    let maxTokens: Int
    let temperature: Double
    let maxSteps: Int

    public init(apiKey: String? = nil, maxTokens: Int = 200, temperature: Double = 0, maxSteps: Int = 10) {
        guard let apiKey = apiKey ?? Environment.apiKey else {
            fatalError("You must provide an API Key with a Config, or as an OPEN_AI_KEY env var")
        }

        self.apiKey = apiKey
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.maxSteps = maxSteps
    }
}

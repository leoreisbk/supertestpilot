//
//  Config.swift
//  TestPilotKit
//
//  Created by Flávio Caetano on 3/13/23.
//

import Foundation
import OpenAIKit

public struct Config {
    let maxTokens: Int
    let temperature: Double
    let maxSteps: Int
    let openAIConfig: Configuration

    public init(openAIConfig: Configuration, maxTokens: Int = 200, temperature: Double = 0, maxSteps: Int = 10) {
        self.openAIConfig = openAIConfig
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.maxSteps = maxSteps
    }
}

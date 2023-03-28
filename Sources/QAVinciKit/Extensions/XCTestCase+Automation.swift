//
//  XCTest+Automation.swift
//  QAVinci
//
//  Created by Flávio Caetano on 3/13/23.
//

import Foundation
import XCTest

public extension XCTestCase {
    @MainActor
    func automate(config: Config = .init(), objective: String) async throws {
        let runner = Runner(config: config)
        defer {
            Task {
                try await runner.httpClient.shutdown()
            }
        }

        let app = XCUIApplication()
        app.launch()
        var lastCommand: String?
        let jsonDecoder = JSONDecoder()

        for _ in 0..<config.maxSteps {
            let jsonCommand = try await runner.getCompletionResponse(
                for: app.debugDescription.simplifyUI(),
                last: lastCommand,
                objective: objective
            )
            guard let jsonCommand = jsonCommand else {
                XCTFail("OpenAI returned empty response")
                return
            }

            // Parse the response
            lastCommand = jsonCommand
            let instruction = try jsonDecoder.decode(Instruction.self, from: Data(jsonCommand.utf8))
            Logging.info(" ↳ \(instruction.description)")

            // Execute the instruction
            switch instruction {
            case let .assert(answer: answer, expected: expected, reason: _):
                XCTAssertEqual(answer, expected, instruction.description)

            case let .type(type: type, label: label, text: text, reason: _):
                let match = try await getElement(from: runner, app: app, type: type, label: label)
                match.waitForExistenceIfNecessary(timeout: 10)
                match.tap()
                match.typeText(text)

            case let .tap(type: type, label: label, reason: _):
                let match = try await getElement(from: runner, app: app, type: type, label: label)
                match.waitForExistenceIfNecessary(timeout: 10)
                match.tap()

            case .scrollDown:
                app.swipeDown(velocity: .slow)

            case .scrollUp:
                app.swipeUp(velocity: .slow)

            case .goBack:
                let match = app.navigationBars.buttons.element(boundBy: .zero)
                match.tap()

            case let .wait(seconds, reason: _):
                try await Task.sleep(for: .seconds(seconds))

            case .done:
                return
            }
        }

        throw "Maximum number of steps exceeded (\(config.maxSteps))"
    }

    private func getElement(from runner: Runner, app: XCUIElement, type: XCUIElement.ElementType, label: String) async throws -> XCUIElement {
        let match = app.firstMatch(of: type, label: label)
        guard !match.exists else {
            return match
        }

        let ui = try app.debugDescription.simplifyUI().replacing(Regex("^(?!\(type.description)).*\n").anchorsMatchLineEndings(), with: "")
        let line = try await runner.searchEmbeddings(input: ui, query: label, n: 1).first ?? ""
        let newLabel = line.firstMatch(of: #/label: '(.*?)'($|,)/#)!

        return app.firstMatch(of: type, label: String(newLabel.output.1))
    }
}

extension String: LocalizedError {
    public var errorDescription: String? { self }
}

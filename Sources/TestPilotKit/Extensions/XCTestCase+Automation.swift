//
//  XCTest+Automation.swift
//  TestPilotKit
//
//  Created by Flávio Caetano on 3/13/23.
//

import Foundation
import XCTest

public extension XCTestCase {
    @MainActor
    func automate(
        config: Config = .init(),
        objective: String,
        bundleId: String? = nil,
        shouldRecordSteps: Bool = false
    ) async throws {
        if shouldRecordSteps {
            Logging.info("** Recording Steps **")
        }
        
        let persistenceManager = PersistenceManager(objective: objective)
        
        let runner = Runner(config: config)
        defer {
            Task {
                try await runner.httpClient.shutdown()
            }
        }

        let app: XCUIApplication
        if let bundleId = bundleId {
            app = XCUIApplication(bundleIdentifier: bundleId)
        } else {
            app = XCUIApplication()
        }

        app.launch()
        var lastCommand: String?
        let jsonDecoder = JSONDecoder()

        for stepIndex in 0..<config.maxSteps {
            
            let commandToExecute: String
            if !shouldRecordSteps, let command = persistenceManager.getStep(index: stepIndex) {
                commandToExecute = command
            } else {
                let jsonCommand = try await runner.getCompletionResponse(
                    for: app.debugDescription.simplifyUI(),
                    last: lastCommand,
                    objective: objective
                )
                guard let jsonCommand = jsonCommand else {
                    XCTFail("OpenAI returned empty response")
                    return
                }
                
                persistenceManager.recordStep(jsonCommand)
                
                commandToExecute = jsonCommand
            }
            
            lastCommand = commandToExecute
            
            // Parse the response
            let instruction = try jsonDecoder.decode(Instruction.self, from: Data(commandToExecute.utf8))
            Logging.info(" ↳ \(instruction.description)")

            // Execute the instruction
            switch instruction {
            case let .assert(answer: answer, expected: expected, reason: _):
                XCTAssertEqual(answer, expected, instruction.description)

            case let .type(type: type, label: label, text: text, reason: _):
                if let match = try await getElement(from: runner, app: app, type: type, label: label) {
                    match.waitForExistenceIfNecessary(timeout: 10)
                    match.tap()
                    match.typeText(text)
                } else {
                    XCTFail("Could not find element of type: [\(type)], with label: [\(label)]")
                }
            case let .tap(type: type, label: label, reason: _):
                if let match = try await getElement(from: runner, app: app, type: type, label: label) {
                    match.waitForExistenceIfNecessary(timeout: 10)
                    match.tap()
                } else {
                    XCTFail("Could not find element of type: [\(type)], with label: [\(label)]")
                }
            case .scrollUp:
                app.swipeDown(velocity: .slow)

            case .scrollDown:
                app.swipeUp(velocity: .slow)

            case .goBack:
                let match = app.navigationBars.buttons.element(boundBy: .zero)
                match.tap()

            case let .wait(seconds, reason: _):
                try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))

            case .done:
                persistenceManager.persistSteps()
                return
            }
        }

        throw "Maximum number of steps exceeded (\(config.maxSteps))"
    }

    private func getElement(from runner: Runner, app: XCUIElement, type: XCUIElement.ElementType, label: String) async throws -> XCUIElement? {
        let match = app.firstMatch(of: type, label: label)
        guard !match.exists else {
            return match
        }

        let uiDump = app.debugDescription.simplifyUI()
        let ui = try NSRegularExpression(pattern: "^(?!\(type.description)).*\\n", options: .anchorsMatchLines)
            .stringByReplacingMatches(in: uiDump, options: [], range: NSMakeRange(0, uiDump.count), withTemplate: "")
        let line = try await runner.searchEmbeddings(input: ui, query: label, n: 1).first ?? ""
        let labelMatch = try NSRegularExpression(pattern: "label: '(?<label>.*?)'($|,)", options: [])
            .firstMatch(in: line, options: [], range: NSMakeRange(0, line.count))

        guard let matchedLabel = labelMatch else { return nil }
        let range = matchedLabel.range(withName: "label")

        return app.firstMatch(of: type, label: (line as NSString).substring(with: range))
    }
}

extension String: LocalizedError {
    public var errorDescription: String? { self }
}

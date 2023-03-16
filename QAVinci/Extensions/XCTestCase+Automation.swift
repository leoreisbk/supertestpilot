//
//  XCTest+Automation.swift
//  QAVinci
//
//  Created by Flávio Caetano on 3/13/23.
//

import Foundation
import XCTest

public extension XCTestCase {
    func automateExpectation(
        config: Config = .init(),
        objective: String,
        expectedResult: String,
        expectationDescription: String? = nil,
        timeout: TimeInterval = 600 // 10min
    ) {
        let exp = expectation(description: objective)

        Task {
            let result = await self.automate(config: config, objective: objective)

            XCTAssertEqual(result, expectedResult)
            exp.fulfill()
        }

        waitForExpectations(timeout: timeout)
    }

    @MainActor @discardableResult
    func automate(config: Config = .init(), objective: String) async -> String? {
        let runner = Runner(config: config)
        defer {
            Task {
                try await runner.httpClient.shutdown()
            }
        }

        do {
            let result = try await nonThrowingAutomation(runner: runner, objective: objective)
            try await runner.httpClient.shutdown()
            return result
        } catch let err {
            dump(err)
            XCTFail(err.localizedDescription)
        }

        return nil
    }

    @MainActor @discardableResult
    private func nonThrowingAutomation(runner: Runner, objective: String) async throws -> String? {
        let jsonDecoder = JSONDecoder()
        let app = XCUIApplication()
        app.launch()

        print("\nStrategizing how to split the objective in tasks...")
        let steps = try await runner.getCompletionSetup(objective: objective)
        print("Done! Dividing work in these steps: ")
        steps.enumerated().forEach { idx, step in
            print("\(idx + 1). \(step)")
        }

        for curStep in steps {
            let uiDump = app.simpleUI

            print("\nExecuting step: '\(curStep)'")

            let jsonCommand = try await runner.getCompletionResponse(for: uiDump, objective: curStep)
            guard let jsonCommand = jsonCommand else {
                return nil
            }

            // Execute the response
            let instruction = try jsonDecoder.decode(Instruction.self, from: Data(jsonCommand.utf8))

            switch instruction {
            case .stop(answer: let answer):
                return answer

            case let .type(type: type, label: label, text: text):
                let match = app.descendants(matching: type)[label]
                match.waitForExistenceIfNecessary(timeout: 10)
                match.tap()
                match.typeText(text)

            case let .tap(type: type, label: label):
                let match = try await getElement(from: runner, app: app, ui: uiDump, type: type, label: label)
                match.waitForExistenceIfNecessary(timeout: 10)
                match.tap()

            case .scrollDown:
                app.swipeDown(velocity: .slow)

            case .scrollUp:
                app.swipeUp(velocity: .slow)

            case .goBack:
                let match = app.navigationBars.buttons.element(boundBy: .zero)
                match.tap()

            case let .wait(seconds):
                try await Task.sleep(for: .seconds(seconds))
            }
        }

        return nil
    }

    private func getElement(from runner: Runner, app: XCUIElement, ui: String, type: XCUIElement.ElementType, label: String) async throws -> XCUIElement {
        let match = app.firstMatch(of: type, label: label)
        guard !match.exists else {
            return match
        }

        let ui = try ui.replacing(Regex("^(?!\(type.description)).*\n").anchorsMatchLineEndings(), with: "")
        let line = try await runner.searchEmbeddings(input: ui, query: label, n: 1).first ?? ""
        let newLabel = line.firstMatch(of: /label: '(.*?)'($|,)/)!

        return app.firstMatch(of: type, label: String(newLabel.output.1))
    }
}

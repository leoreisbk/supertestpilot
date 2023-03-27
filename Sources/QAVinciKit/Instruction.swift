//
//  Command.swift
//  QAVinci
//
//  Created by Flávio Caetano on 3/13/23.
//

import Foundation
import XCTest

enum Instruction: Decodable {
    enum CodingKeys: String, CodingKey {
        case cmd, type, label, text, answer, seconds, expected
    }

    case tap(type: XCUIElement.ElementType, label: String)
    case type(type: XCUIElement.ElementType, label: String, text: String)
    case assert(answer: String?, expected: String)
    case scrollDown
    case scrollUp
    case goBack
    case wait(seconds: TimeInterval)
    case done

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cmd = try container.decode(Command.self, forKey: .cmd)
        switch cmd {
        case .tap:
            let type = try container.decode(XCUIElement.ElementType.self, forKey: .type)
            let label = try container.decode(String.self, forKey: .label)

            self = .tap(type: type, label: label)

        case .type:
            let type = try container.decode(XCUIElement.ElementType.self, forKey: .type)
            let label = try container.decode(String.self, forKey: .label)
            let text = try container.decode(String.self, forKey: .text)

            self = .type(type: type, label: label, text: text)

        case .assert:
            let answer = try? container.decode(String.self, forKey: .answer)
            let expected = try container.decode(String.self, forKey: .expected)

            self = .assert(answer: answer, expected: expected)

        case .scrollDown:
            self = .scrollDown

        case .scrollUp:
            self = .scrollUp

        case .goBack:
            self = .goBack

        case .wait:
            let seconds = try container.decode(TimeInterval.self, forKey: .seconds)
            self = .wait(seconds: seconds)

        case .done:
            self = .done
        }
    }
}

private extension Instruction {
    enum Command: String, Decodable {
        case tap, type, assert, scrollDown, scrollUp, goBack, wait, done
    }
}

extension Instruction: CustomStringConvertible {
    var description: String {
        switch self {
        case let .assert(answer: answer, expected: expectation):
            return "Asserting expected value (\(expectation)) equals to discovered value (\(answer ?? "N/A"))"

        case let .tap(type: type, label: label):
            return "Tapping element - \(type) - (\(label))"

        case let .wait(seconds: seconds):
            return "Waiting for \(seconds) seconds"

        case let .type(type: type, label: label, text: text):
            return "Typing (\(text)) into element - \(type) - (\(label))"

        case .done: return "Objective fulfilled"
        case .goBack: return "Going back"
        case .scrollDown: return "Scrolling down"
        case .scrollUp: return "Scrolling up"
        }
    }
}

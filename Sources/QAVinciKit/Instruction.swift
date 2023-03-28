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
        case cmd, type, label, text, answer, seconds, expected, reason
    }

    case tap(type: XCUIElement.ElementType, label: String, reason: String)
    case type(type: XCUIElement.ElementType, label: String, text: String, reason: String)
    case assert(answer: String?, expected: String, reason: String)
    case scrollDown(reason: String)
    case scrollUp(reason: String)
    case goBack(reason: String)
    case wait(seconds: TimeInterval, reason: String)
    case done(reason: String)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cmd = try container.decode(Command.self, forKey: .cmd)
        let reason = try container.decode(String.self, forKey: .reason)

        switch cmd {
        case .tap:
            let type = try container.decode(XCUIElement.ElementType.self, forKey: .type)
            let label = try container.decode(String.self, forKey: .label)

            self = .tap(type: type, label: label, reason: reason)

        case .type:
            let type = try container.decode(XCUIElement.ElementType.self, forKey: .type)
            let label = try container.decode(String.self, forKey: .label)
            let text = try container.decode(String.self, forKey: .text)

            self = .type(type: type, label: label, text: text, reason: reason)

        case .assert:
            let answer = try? container.decode(String.self, forKey: .answer)
            let expected = try container.decode(String.self, forKey: .expected)

            self = .assert(answer: answer, expected: expected, reason: reason)

        case .scrollDown:
            self = .scrollDown(reason: reason)

        case .scrollUp:
            self = .scrollUp(reason: reason)

        case .goBack:
            self = .goBack(reason: reason)

        case .wait:
            let seconds = try container.decode(TimeInterval.self, forKey: .seconds)
            self = .wait(seconds: seconds, reason: reason)

        case .done:
            self = .done(reason: reason)
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
        case let .assert(answer: answer, expected: expectation, reason: reason):
            return "\(reason) - Asserting expected value (\(expectation)) equals to discovered value (\(answer ?? "N/A"))"

        case let .tap(type: type, label: label, reason: reason):
            return "\(reason) - Tapping '\(label)' \(type)"

        case let .wait(seconds: seconds, reason: reason):
            return "\(reason) - Waiting for \(seconds) seconds"

        case let .type(type: type, label: label, text: text, reason: reason):
            return "\(reason) - Typing '\(text)' into '\(label)' \(type)"

        case let .done(reason: reason): return reason
        case let .goBack(reason: reason): return reason
        case let .scrollDown(reason: reason): return reason
        case let .scrollUp(reason: reason): return reason
        }
    }
}

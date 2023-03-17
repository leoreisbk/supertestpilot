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
        case cmd, type, label, text, answer, seconds
    }

    case tap(type: XCUIElement.ElementType, label: String)
    case type(type: XCUIElement.ElementType, label: String, text: String)
    case stop(answer: String?)
    case scrollDown
    case scrollUp
    case goBack
    case wait(seconds: TimeInterval)

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

        case .stop:
            let answer = try? container.decode(String.self, forKey: .answer)

            self = .stop(answer: answer)

        case .scrollDown:
            self = .scrollDown

        case .scrollUp:
            self = .scrollUp

        case .goBack:
            self = .goBack

        case .wait:
            let seconds = try container.decode(TimeInterval.self, forKey: .seconds)
            self = .wait(seconds: seconds)
        }
    }
}

private extension Instruction {
    enum Command: String, Decodable {
        case tap, type, stop, scrollDown, scrollUp, goBack, wait
    }
}

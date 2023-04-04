//
//  Environment.swift
//  QAVinci
//
//  Created by Flávio Caetano on 3/13/23.
//

import Foundation

enum Environment {
    static var apiKey: String? {
        ProcessInfo.processInfo.environment["OPEN_AI_KEY"]
    }

    static var wsReceiver: String? {
        ProcessInfo.processInfo.environment["WS_RECEIVER"]
    }
}

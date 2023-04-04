//
//  Logging.swift
//  QAVinciKit
//
//  Created by Flávio Caetano on 3/20/23.
//

import Foundation
import Network

public class Logging {
    static let shared = Logging()

    private var task: URLSessionWebSocketTask?
    private var receiver: String?

    private init() {
        guard let url = Environment.wsServerURL else {
            print("Invalid websocket logging server URL defined on environment variable WS_SERVER")
            return
        }

        guard let receiver = Environment.wsReceiver else {
            print("Websocket logging receiver not found on environment variable WS_RECEIVER")
            return
        }

        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        self.receiver = receiver

        func receive() {
            task.receive { result in
                switch result {
                case .success(let msg):
                    print(msg.content ?? "Error: Websocket message can't be displayed")
                    receive() // recursion

                case .failure(let err):
                    dump(err)
                }
            }
        }
        receive()

        task.resume()
    }

    public static func info(_ msg: String) {
        guard let task = shared.task, let receiver = shared.receiver else {
            print("Message not sent to logging server - \(msg)")
            return
        }

        do {
            try task.send(.message(receiver: receiver, text: msg)) { error in
                if let error = error {
                    print("An unexpected issue occurred: \(error)")
                }
            }
        } catch {
            print("Couldn't log message: \(error)")
        }
    }
}

private extension Logging {
    struct Message: Codable {
        let rcv: String
        let msg: String
    }
}

private extension URLSessionWebSocketTask.Message {
    static func message(receiver: String, text: String) throws -> URLSessionWebSocketTask.Message {
        try .data(JSONEncoder().encode(Logging.Message(rcv: receiver, msg: text)))
    }

    var content: String? {
        switch self {
        case .string(let result): return result
        case .data(let data): return String(data: data, encoding: .utf8)
        @unknown default: return nil
        }
    }
}


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

    private let task: URLSessionWebSocketTask

    private init() {
        // TODO: host on a remote server and add an option to use a custom server
        self.task = URLSession.shared.webSocketTask(with: URL(string: "ws://6.tcp.ngrok.io:16192")!)

        func receive() {
            task.receive { result in
                switch result {
                case .success(let msg):
                    print(msg.content)
                    receive()

                case .failure(let err):
                    dump(err)
                }
            }
        }
        receive()

        task.resume()
    }

    public static func info(_ msg: String) {
        do {
            try shared.task.send(.message(receiver: Environment.wsReceiver!, text: msg)) { error in
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


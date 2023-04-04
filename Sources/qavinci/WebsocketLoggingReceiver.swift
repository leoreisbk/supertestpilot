//
//  WebsocketLoggingReceiver.swift
//  
//
//  Created by Flávio Caetano on 3/30/23.
//

import Foundation
import Network
import Logging

private let logger = Logger(label: #file.lastPathComponent)
class WebsocketLoggingReceiver {
    private let task: URLSessionWebSocketTask
    private let address: String
    init(address: String) {
        logger.debug("Initializing websocket logger")

        // TODO: host on a remote server and add an option to use a custom server
        self.task = URLSession.shared.webSocketTask(with: URL(string: "ws://6.tcp.ngrok.io:16192")!)
        self.address = address
    }

    func startServer() throws {
        logger.debug("Starting websocket receiver: \(address)")

        Task {
            repeat {
                let msg = try await task.receive()
                if let msg = msg.content {
                    logger.info(.init(stringLiteral: msg))
                } else {
                    logger.warning("Received empty websocket message: \(msg)")
                }
            } while true
        }

        task.resume()

        logger.debug("Registering websocket receiver: \(address)")
        try task.send(
            .data(JSONSerialization.data(withJSONObject: ["rcv": address]))
        ) { error in
            if let error = error {
                logger.error("Failed to register websocket receiver: \(error)")
            }
        }
    }
}

private extension URLSessionWebSocketTask.Message {
    var content: String? {
        switch self {
        case .string(let result): return result
        case .data(let data): return String(data: data, encoding: .utf8)
        @unknown default: return nil
        }
    }
}

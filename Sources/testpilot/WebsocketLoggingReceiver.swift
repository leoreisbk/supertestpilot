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
class WebsocketLoggingReceiver: NSObject {
    private static let pingInterval: TimeInterval = 30

    private let task: URLSessionWebSocketTask
    private let address: String
    private let pingTimerQueue = DispatchQueue(label: "ws ping queue")

    init(address: String, serverURL: URL) {
        logger.debug("Initializing websocket logger")

        self.task = URLSession.shared.webSocketTask(with: serverURL)
        self.address = address

        super.init()
    }

    func startServer() throws {
        logger.debug("Starting websocket receiver: \(address)")
        schedulePing()

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

    private func schedulePing() {
        // Couldn't get Timer.schedule to work for whatever reason
        pingTimerQueue.asyncAfter(deadline: .now() + Self.pingInterval) { [weak self] in
            logger.debug("Pinging websocket server")

            self?.task.sendPing {
                if let error = $0 {
                    logger.error("Disconnected from logging server: \(error)")
                } else {
                    logger.debug("Websocket server responded with pong")
                    self?.schedulePing()
                }
            }
        }
    }
}

extension WebsocketLoggingReceiver: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard closeCode != .normalClosure else {
            // client explicitly disconnected
            return
        }

        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
        logger.error("Logging server disconnected unexpectedly")
        logger.debug("Reason: \(reasonString ?? "N/A")")
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

//
//  main.swift
//  qavinci
//
//  Created by Flávio Caetano on 3/16/23.
//

import Foundation
import Logging
import LoggingFormatAndPipe

// MARK: - Logging config
// This needs to be called before any loggers are created :/
private let isVerbose = (try? QAVinciCommand.parse(Array(ProcessInfo.processInfo.arguments[1...])))?.verbose ?? false
LoggingSystem.bootstrap { msg in
    var res = LoggingFormatAndPipe.Handler(
        formatter: BasicFormatter(isVerbose ? [.timestamp, .level, .message] : [.message]),
        pipe: LoggerTextOutputStreamPipe.standardOutput
    )
    res.logLevel = isVerbose ? .debug : .info
    return res
}

// MARK: - Sig trap
signal(SIGINT, SIG_IGN)
let sig = DispatchSource.makeSignalSource(signal: SIGINT)
sig.setEventHandler {
   ProcessPool.shared.terminateRunningProcesses()
}

sig.resume()

// MARK: - MAIN
QAVinciCommand.main()

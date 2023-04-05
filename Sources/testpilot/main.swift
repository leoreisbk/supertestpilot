//
//  main.swift
//  testpilot
//
//  Created by Flávio Caetano on 3/16/23.
//

import Foundation
import Logging
import LoggingFormatAndPipe

do {
    let args = Array(ProcessInfo.processInfo.arguments[1...])
    let configReader = ConfigFileReader(args: args)
    
    let cmdArgs = try configReader?.getArguments() ?? args

    // MARK: - Logging config
    // This needs to be called before any loggers are created :/
    let isVerbose = configReader?.verbose == true
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
#if DEBUG
    print(ProcessInfo.processInfo.arguments[0])
#endif

    let cmd = try TestPilotCommand.parse(cmdArgs)
    try cmd.run()
} catch {
    TestPilotCommand.exit(withError: error)
}

//
//  ProcessPool.swift
//  testpilot
//
//  Created by Flávio Caetano on 3/20/23.
//

import Foundation

class ProcessPool {
    static let shared = ProcessPool()

    var processes = Set<Process>()

    func terminateRunningProcesses() {
        processes
            .filter { $0.isRunning }
            .forEach { proc in
                proc.terminate()
            }
    }

    func run(process: Process) throws {
        processes.insert(process)
        let termHandler = process.terminationHandler
        process.terminationHandler = {
            termHandler?($0)
            self.processes.remove($0)
        }

        try process.run()
    }
}

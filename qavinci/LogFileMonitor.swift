//
//  LogFileMonitor.swift
//  qavinci
//
//  Created by Flávio Caetano on 3/21/23.
//

import Foundation

class LogFileMonitor {
    static let shared = LogFileMonitor()
    private init() {}

    private var dispatchRead: DispatchSourceRead?

    func monitor(logFile: String) throws {
        let fileHandle = try FileHandle(forReadingFrom: URL(filePath: logFile))
        let readFile = DispatchSource.makeReadSource(fileDescriptor: fileHandle.fileDescriptor)
        readFile.setEventHandler {
            if let data = try? fileHandle.readToEnd() {
                try? FileHandle.standardOutput.write(contentsOf: data)
            }
        }

        readFile.resume()
        dispatchRead = readFile
    }
}

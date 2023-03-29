//
//  Logging.swift
//  QAVinciKit
//
//  Created by Flávio Caetano on 3/20/23.
//

import Foundation

public class Logging {
    static let shared = Logging()

    private var writer: Writer

    private init() {
        #if targetEnvironment(simulator)
        do {
            guard let filePath = Environment.logFile else {
                throw ErrorCode.noEnvVar
            }

            if !FileManager.default.fileExists(atPath: filePath) {
                FileManager.default.createFile(atPath: filePath, contents: nil)
            }
            
            guard let fileHandle = FileHandle(forWritingAtPath: filePath) else {
                throw ErrorCode.fileNotCreated
            }

            self.writer = Writer(fileHandle: fileHandle)
        } catch _ {
            fatalError("Couldn't create logger")
        }
        #else
        self.writer = Writer(fileHandle: .nullDevice)
        #endif
    }

    public static func info(_ msg: String) {
        print(msg, to: &Self.shared.writer)
    }
}

private extension Logging {
    struct Writer: TextOutputStream {
        let fileHandle: FileHandle

        func write(_ string: String) {
            _ = try? fileHandle.seekToEnd()
            try? fileHandle.write(contentsOf: Data(string.utf8))
        }
    }

    enum ErrorCode: Error {
        case noEnvVar, fileNotCreated
    }
}

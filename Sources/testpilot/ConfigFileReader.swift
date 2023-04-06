//
//  ConfigFileReader.swift
//  testpilot
//
//  Created by Flávio Caetano on 4/5/23.
//

import Foundation
import ArgumentParser
import Logging

private let logger = Logger(label: #file.lastPathComponent)
class ConfigFileReader {
    let testsPath: String
    let configPath: URL
    var verbose: Bool

    init?(args: [String]) {
        guard
            let cmd = try? Command.parse(args),
            let cfg = cmd.config,
            FileManager.default.fileExists(atPath: cfg.path(percentEncoded: false))
        else {
            logger.debug("Config file not provided or doesn't exist")
            return nil
        }

        verbose = cmd.verbose
        configPath = cfg
        testsPath = cmd.testsPath

        logger.debug("Config file: \(cfg.path(percentEncoded: false))")
    }

    func getArguments() throws -> [String] {
        let data = try Data(contentsOf: configPath)
        guard let jsonContent = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ValidationError("Bad config file")
        }

        let result = jsonContent.reduce([testsPath]) { partialResult, kv in
            let key = "--\(kv.key)"
            guard let boolValue = kv.value as? Bool else {
                return partialResult + [key, "\(kv.value)"]
            }

            if boolValue {
                if kv.key == "verbose" {
                    self.verbose = true
                }

                return partialResult + [key]
            } else {
                return partialResult
            }
        }

        logger.debug("Arguments read from config file: \(result)")
        return result
    }
}

extension ConfigFileReader {
    struct Command: ParsableCommand {
        @Argument(completion: .directory)
        var testsPath: String = TestPilotCommand.DefaultValues.testsPath

        @Option(name: .shortAndLong, transform: { URL(filePath: $0) })
        var config: URL? = URL(
            filePath: FileManager.default
                .currentDirectoryPath
                .appendingPathComponent(TestPilotCommand.DefaultValues.configFileName)
        )

        @Flag(name: .shortAndLong)
        var verbose = false

        func run() throws {
            // no-op
        }
    }
}

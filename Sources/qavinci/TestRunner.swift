//
//  RunCommand.swift
//  qavinci
//
//  Created by Flávio Caetano on 3/17/23.
//

import Foundation
import Logging
import ArgumentParser

private let logger = Logger(label: #file.lastPathComponent)
struct TestRunner {
    let testProjectPath: String
    let launchSimulator: Bool

    private let xcodePath: URL
    private let destination: Device

    private var xcodeLogFileURL: URL = {
        Constants.tempDir
            .appending(component: "xcodebuild-\(ISO8601DateFormatter().string(from: Date())).log")
    }()

    init(testProjectPath: String, launchSimulator: Bool, destination: Device) throws {
        self.testProjectPath = testProjectPath
        self.launchSimulator = launchSimulator
        self.destination = destination
        self.xcodePath = try Xcode.getXcodePath()
    }

    func run(verbose: Bool) throws {
        if launchSimulator {
            try launchSimulator(uuid: destination.udid)
        }

        logger.info("Preparing tests... (this may take a few minutes)")
        try runTests(verbose: verbose, action: "build-for-testing")
        logger.info("Running tests on \(destination.name)")
        try runTests(verbose: verbose, action: "test-without-building")
    }

    private func runTests(verbose: Bool, action: String) throws {
        let fileHandle = verbose ? FileHandle.standardOutput : try makeXcodeFileHandle()

        let platform: String
        if destination.isSimulator {
            platform = "platform=iOS Simulator,id=\(destination.udid)"
        } else {
            platform = "platform=iOS,id=\(destination.udid)"
        }
        
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcodebuild")
        process.standardError = fileHandle
        process.standardOutput = fileHandle
        process.arguments = [
            "-project", testProjectPath,
            "-scheme", Constants.testProjectName,
            "-destination", platform,
            action
        ]

        try ProcessPool.shared.run(process: process)
        process.waitUntilExit()

        let xcodeExitCode = ExitCode(process.terminationStatus)
        if xcodeExitCode.isSuccess == false && process.terminationStatus != SIGTERM  {
            logger.error("""

            Testing failed due to unexpected issue. Check the build logs on:
            \(xcodeLogFileURL.path(percentEncoded: false))
            """)

            throw xcodeExitCode
        }
    }

    private func launchSimulator(uuid: String) throws {
        logger.debug("Launching iOS Simulator")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = ["-a", "Simulator", "--args", "-CurrentDeviceUDID", uuid]

        try ProcessPool.shared.run(process: process)
    }

    private func makeXcodeFileHandle() throws -> FileHandle {
        logger.debug("xcodebuild logfile: \(xcodeLogFileURL.path(percentEncoded: false))")
        FileManager.default.createFile(atPath: xcodeLogFileURL.path(percentEncoded: false), contents: nil)
        return try FileHandle(forWritingTo: xcodeLogFileURL)
    }
}

enum ErrorCase: Error {
    case xcodeNotFound, deviceNotFound
}

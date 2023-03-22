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
    private let deviceName = "iPhone 14 Pro"

    private var xcodeLogFileURL: URL = {
        Constants.tempDir
            .appending(component: "xcodebuild-\(ISO8601DateFormatter().string(from: Date())).log")
    }()

    init(testProjectPath: String, launchSimulator: Bool) throws {
        self.testProjectPath = testProjectPath
        self.launchSimulator = launchSimulator
        self.xcodePath = try Self.getXcodePath()
    }

    func run(verbose: Bool) throws {
        // TODO: find highest device
        logger.debug("Finding UUID of \(deviceName)")
        guard let uuid = try findDeviceUUID(name: deviceName) else {
            logger.debug("UUID not found. Aborting")
            throw ErrorCase.deviceNotFound
        }

        logger.debug("Found device \(uuid)")

        if launchSimulator {
            try launchSimulator(uuid: uuid)
        }

        logger.info("Starting tests on \(deviceName)")
        try runTests(uuid: uuid, verbose: verbose)
    }

    private func runTests(uuid: String, verbose: Bool) throws {
        let fileHandle = verbose ? FileHandle.standardOutput : try makeXcodeFileHandle()

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcodebuild")
        process.standardError = fileHandle
        process.standardOutput = fileHandle
        process.arguments = [
            "-project", testProjectPath,
            "-scheme", Constants.testProjectName,
            "-sdk", "iphonesimulator",
            "-destination", "platform=iOS Simulator,id=\(uuid)",
            "test"
        ]

        try ProcessPool.shared.run(process: process)
        process.waitUntilExit()

        let xcodeExitCode = ExitCode(process.terminationStatus)
        if xcodeExitCode.isSuccess == false {
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

    private func findDeviceUUID(name: String) throws -> String? {
        let output = Pipe()
        let process = Process()
        process.executableURL = xcodePath.appending(component: "usr/bin/simctl")
        process.standardOutput = output
        process.arguments = ["list", "devices", name, "-j"]

        try ProcessPool.shared.run(process: process)
        process.waitUntilExit()

        guard let data = try output.fileHandleForReading.readToEnd() else {
            return nil
        }

        let simulators = try JSONDecoder().decode(Simulators.self, from: data)
        return simulators.devices
            .sorted { $1.key < $0.key }
            .compactMap { $0.value }
            .flatMap { $0 }
            .first(where: { ($0 as Device).name == name })?
            .udid
    }

    private static func getXcodePath() throws -> URL {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcode-select")
        process.standardOutput = output
        process.arguments = ["--print-path"]

        try ProcessPool.shared.run(process: process)
        process.waitUntilExit()

        guard let path = try output.fileHandleForReading.readToEnd()
            .flatMap({ String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) })
        else {
            throw ErrorCase.xcodeNotFound
        }

        return URL(filePath: path)
    }

    private func makeXcodeFileHandle() throws -> FileHandle {
        logger.debug("xcodebuild logfile: \(xcodeLogFileURL.path(percentEncoded: false))")
        FileManager.default.createFile(atPath: xcodeLogFileURL.path(percentEncoded: false), contents: nil)
        return try FileHandle(forWritingTo: xcodeLogFileURL)
    }
}

private extension TestRunner {
    struct Simulators: Decodable {
        let devices: [String: [Device]]
    }

    struct Device: Decodable {
        let udid: String
        let name: String
    }

    enum ErrorCase: Error {
        case xcodeNotFound, deviceNotFound
    }
}

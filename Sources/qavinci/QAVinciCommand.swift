//
//  QAVinciCommand.swift
//  qavinci
//
//  Created by Flávio Caetano on 3/21/23.
//

import Foundation
import ArgumentParser
import Logging

private let logger = Logger(label: #file.lastPathComponent)
struct QAVinciCommand: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "qavinci")

    @Argument(
        help: """
        The path to the folder containing the .\(Constants.testFileExt) test files. Can be a specific test case to be \
        executed (default: .)
        """,
        completion: .directory,
        transform: { WorkDir(path: $0) }
    )
    var testsPath = WorkDir(path: FileManager.default.currentDirectoryPath)

    @Option(
        name: .shortAndLong,
        parsing: .scanningForValue,
        help: "The app's bundle id to be tested"
    )
    var bundleId: String!

    @Option(
        name: .shortAndLong,
        parsing: .scanningForValue,
        help: "The device where the tests are going to run. Ex.: platform=iOS,id=[DEVICE_UDID] or platform=iOS Simulator,id=[DEVICE_UDID]"
    )
    var destination: String?
    
    @Option(
        name: .shortAndLong,
        parsing: .scanningForValue,
        help: "The OpenAI API Key to be used. Can be set as env var OPEN_AI_KEY"
    )
    var openAIKey: String!

    @Option(name: .long, help: "The max number of steps that should be executed")
    var maxSteps: UInt8 = 10

    @Option(
        name: .long,
        help: "The URL to the websocket logging server. Must start with `ws://` or `wss://`",
        transform: { string in
            guard let url = URL(string: string) else {
                throw URLError(.badURL)
            }

            return url
        }
    )
    var loggingServer: URL // TODO: provide a default value

    @Flag(name: .shortAndLong, help: "Launches the iOS simulator")
    var launchSim = false

    @Flag(name: .shortAndLong, help: .private)
    var skipRun = false

    @Flag(name: .shortAndLong, help: ArgumentHelp("Verbose output"))
    var verbose = false

    func run() throws {
        let loggingAddress = UUID().uuidString

        // Setting in logging client
        let ws = WebsocketLoggingReceiver(address: loggingAddress, serverURL: loggingServer)
        try ws.startServer()

        let fm = FileManager.default

        // Setting up logging
        logger.debug("Log File: \(Constants.logFilePath)")
        try fm.createDirectory(atPath: Constants.logFilePath.deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: Constants.logFilePath, contents: nil)

        // Creating target directory
        let targetDir = Constants.tempDir
        logger.debug("Creating project on: \(targetDir.path(percentEncoded: false))")
        try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Regenerate the test file
        try TestFileBuilder(
            testsDir: testsPath,
            targetDir: targetDir,
            bundleId: bundleId
        )
        .buildTestFile(maxSteps: maxSteps)

        // Create the project if it doesn't exist
        let testProject = try TestProjectGenerator(
            targetDir: targetDir,
            openAIKey: openAIKey,
            loggingAddress: loggingAddress,
            loggingServerURL: loggingServer
        )
        try testProject.generate()
        
        let destinationDevice: Device
        if
            let destination = destination,
            let udid = extractPlatformAndUDID(from: destination).udid,
            let platform = extractPlatformAndUDID(from: destination).platform
        {
            destinationDevice = Device(udid: udid, name: "", isSimulator: platform.contains("Simulator"))
        } else {
            let devices = try TestDestination.getDevices()
            devices
                .enumerated()
                .forEach { print("\($0.offset): \($0.element.name) \($0.element.osVersion) \($0.element.udid)") }
            
            print("Enter the device number (ex. 12):")
            
            guard let readLineValue = readLine(), let selectedDestinationIndex = Int(readLineValue) else {
                return
            }
            
            destinationDevice = devices[selectedDestinationIndex]
        }
        
        // Run tests
        if !skipRun {
            try TestRunner(
                testProjectPath: testProject.testProjectPath,
                launchSimulator: launchSim,
                destination: destinationDevice
            )
            .run(verbose: false)
        }
    }

    mutating func validate() throws {
        logger.debug("Tests path: '\(testsPath.dirPath.path(percentEncoded: false))'")
        logger.debug("Test case: \(testsPath.testCase ?? "[all]")")

        // Check for OpenAI Key
        openAIKey = openAIKey ?? Environment.apiKey
        guard openAIKey != nil else {
            throw ValidationError("Missing OpenAI API Key")
        }
        logger.debug("OpenAI API Key: \(openAIKey!)")
    }
    
    private func extractPlatformAndUDID(from message: String) -> (platform: String?, udid: String?) {
        let platformRegex = "platform=([^,]+)"
        let udidRegex = "UDID=([A-F\\d\\-]+)"
        
        let platform = message
            .range(of: platformRegex, options: .regularExpression)
            .map { String(message[$0]) }
            .map { $0.replacingOccurrences(of: "platform=", with: "") }
        
        let udid = message
            .range(of: udidRegex, options: .regularExpression)
            .map { String(message[$0]) }
            .map { $0.replacingOccurrences(of: "UDID=", with: "") }
        
        return (platform, udid)
    }
}

extension QAVinciCommand {
    struct WorkDir: Decodable {
        let dirPath: URL
        let testCase: String?

        init(path: String) {
            let url = URL(filePath: path).absoluteURL
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false {
                dirPath = url.deletingLastPathComponent()
                testCase = url.lastPathComponent
            } else {
                dirPath = url
                testCase = nil
            }
        }
    }
}

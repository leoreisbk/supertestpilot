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
        help: "The path to the .xcodeproj to be tested (default: ./*.xcodeproj)",
        completion: .directory,
        transform: { URL(filePath: $0) }
    )
    var project: URL!

    @Option(
        name: .shortAndLong,
        parsing: .scanningForValue,
        help: "The OpenAI API Key to be used. Can be set as env var OPEN_AI_KEY"
    )
    var openAIKey: String!

    @Option(
        name: .long,
        help: "The scheme being tested"
    )
    var scheme: String?

    @Option(name: .long, help: "The max number of steps that should be executed")
    var maxSteps: UInt8 = 10

    @Flag(name: .shortAndLong, help: "Launches the iOS simulator")
    var launchSim = false

    @Flag(name: .shortAndLong, help: .private)
    var skipRun = false

    @Flag(name: .shortAndLong, help: ArgumentHelp("Verbose output"))
    var verbose = false

    func run() throws {
        let fm = FileManager.default

        // Setting up logging
        logger.debug("Log File: \(Constants.logFilePath)")
        try fm.createDirectory(atPath: Constants.logFilePath.deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: Constants.logFilePath, contents: nil)

        // Creating target directory
        let targetDir = Constants.tempDir.appending(component: project.lastPathComponent.deletingPathExtension)
        logger.debug("Creating project on: \(targetDir.path(percentEncoded: false))")
        try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Regenerate the test file
        try TestFileBuilder(testsDir: testsPath, targetDir: targetDir)
            .buildTestFile(maxSteps: maxSteps)

        // Create the project if it doesn't exist
        let testProject = try TestProjectGenerator(
            testedProjectPath: project,
            targetDir: targetDir,
            scheme: scheme,
            openAIKey: openAIKey,
            logFile: Constants.logFilePath
        )
        try testProject.generate()

        // Monitors the output of the tests and redirect to stdout
        try LogFileMonitor.shared.monitor(logFile: Constants.logFilePath)

        if !skipRun {
            try TestRunner(testProjectPath: testProject.testProjectPath, launchSimulator: launchSim)
                .run(verbose: false)
        }
    }

    mutating func validate() throws {
        logger.debug("Tests path: \(testsPath.dirPath.path(percentEncoded: false))")
        logger.debug("Test case: \(testsPath.testCase ?? "[all]")")

        // Checking if tested project is a dir or the .xcodeproj file
        let path = (project ?? testsPath.dirPath).path(percentEncoded: false)
        if !path.hasSuffix(".xcodeproj") {
            let projects = try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.hasSuffix(".xcodeproj") }
            if projects.count == 0 { throw ValidationError("Couldn't find any .xcodeproj") }
            if projects.count > 1 { throw ValidationError("Found multiple .xcodeproj files") }

            project = URL(filePath: path.appendingPathComponent(projects[0])).absoluteURL
        }

        // Check for OpenAI Key
        openAIKey = openAIKey ?? Environment.apiKey
        guard openAIKey != nil else {
            throw ValidationError("Missing OpenAI API Key")
        }
        logger.debug("OpenAI API Key: \(openAIKey!)")
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

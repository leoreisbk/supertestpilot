//
//  main.swift
//  qavinci
//
//  Created by Flávio Caetano on 3/16/23.
//

import Foundation
import ArgumentParser

struct QAVinciCommand: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "qavinci")

    @Argument(
        help: "The path to the folder containing the .\(Constants.testFileExt) test files. Defaults to the current directory",
        completion: .directory,
        transform: { URL(filePath: $0) }
    )
    var testsPath = URL(filePath: ".")

    @Option(
        name: .shortAndLong,
        parsing: .scanningForValue,
        help: ArgumentHelp("The path to the .xcodeproj to be tested"),
        completion: .directory,
        transform: { URL(filePath: $0) }
    )
    var project = URL(filePath: ".")

    @Option(
        name: .shortAndLong,
        parsing: .scanningForValue,
        help: ArgumentHelp("The OpenAI API Key to be used. Can be set as env var OPEN_AI_KEY")
    )
    var openAIKey: String!

    @Flag(name: .shortAndLong, help: "Launches the iOS simulator")
    var launchSim = false

    var testProjectPath: String {
        testsPath
            .appending(component: "\(Constants.testProjectName).xcodeproj")
            .path(percentEncoded: false)
    }

    func run() throws {
        // Regenerate the test file
        try TestFileBuilder(path: testsPath).buildTestFile()

        // Create the project if it doesn't exist
        let testProject = try TestProjectGenerator(testedProjectPath: project, testsPath: testsPath, openAIKey: openAIKey)
        if !FileManager.default.fileExists(atPath: testProjectPath) {
            try testProject.generate()
        }

        try Runner(testProjectPath: testProject.testProjectPath, launchSimulator: launchSim).run()
    }

    mutating func validate() throws {
        // Checking if tested project is a dir or the .xcodeproj file
        let path = project.path(percentEncoded: false)
        if !path.hasSuffix(".xcodeproj") {
            let projects = try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.hasSuffix(".xcodeproj") }
            if projects.count == 0 { throw ValidationError("Couldn't find any .xcodeproj") }
            if projects.count > 1 { throw ValidationError("Found multiple .xcodeproj files") }

            project = URL(filePath: path.appendingPathComponent(projects[0]))
        }

        // Check for OpenAI Key
        openAIKey = openAIKey ?? Environment.apiKey
        guard openAIKey != nil else {
            throw ValidationError("Missing OpenAI API Key")
        }
    }
}

signal(SIGINT, SIG_IGN)
let sig = DispatchSource.makeSignalSource(signal: SIGINT)
sig.setEventHandler {
    ProcessPool.shared.terminateRunningProcesses()
}

sig.resume()
QAVinciCommand.main()

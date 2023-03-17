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
        let testProject = try TestProjectGenerator(testedProjectPath: project, testsPath: testsPath)
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
            if projects.count == 0 { throw Self.ErrorCase.projectNotFound }
            if projects.count > 1 { throw Self.ErrorCase.foundMultipleProjects }

            project = URL(filePath: path.appendingPathComponent(projects[0]))
        }
    }
}

extension QAVinciCommand {
    enum ErrorCase: Error, CustomStringConvertible {
        case projectNotFound, foundMultipleProjects

        var description: String {
            switch self {
            case .projectNotFound: return "Couldn't find any .xcodeproj"
            case .foundMultipleProjects: return "Found multiple .xcodeproj files"
            }
        }
    }
}

//QAVinciCommand.main(["/Users/flaviocaetano/projects/Fruta Test", "-p", "/Users/flaviocaetano/Downloads/FrutaBuildingAFeatureRichAppWithSwiftUI"])
QAVinciCommand.main()

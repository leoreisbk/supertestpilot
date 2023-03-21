//
//  GenProj.swift
//  qavinci
//
//  Created by Flávio Caetano on 3/16/23.
//

import Foundation
import ArgumentParser
import XcodeGenKit
import ProjectSpec
import PathKit
import XcodeProj
import Logging

private let logger = Logger(label: #file.lastPathComponent)
struct TestProjectGenerator {
    let testsPath: String

    let project: Project

    var testProjectPath: String {
        project.defaultProjectPath.string
    }

    init(testedProjectPath: URL, testsPath: URL, openAIKey: String, logFile: String) throws {
        let projectPath = testedProjectPath.path(percentEncoded: false)
        self.testsPath = testsPath.appending(component: Constants.testProjectDir).path(percentEncoded: false)
        logger.debug("Initializing project on \(self.testsPath)")

        let existingProject = try XcodeProj(pathString: projectPath)
        guard let scheme = existingProject.sharedData?.schemes.first?.name else {
            throw ValidationError("Couldn't find any schemes available in the given project")
        }

        self.project = try Project(
            basePath: Path(self.testsPath),
            name: Constants.testProjectName,
            targets: [
                Target(
                    name: Constants.testProjectName,
                    type: .uiTestBundle,
                    platform: .iOS,
                    settings: Settings(dictionary: ["TEST_TARGET_NAME": scheme]),
                    sources: [
                        TargetSource(
                            path: self.testsPath,
                            includes: ["*.swift"],
                            createIntermediateGroups: true
                        ),
                    ],
                    dependencies: [
                        Dependency(type: .target, reference: "Host/\(scheme)"),
                        Dependency(type: .target, reference: "QAVinci/QAVinciKit"),
                    ],
                    info: Plist(path: "Info.plist")
                ),
            ],
            schemes: [
                Scheme(
                    name: Constants.testProjectName,
                    build: Scheme.Build(targets: [
                        Scheme.BuildTarget(target: TestableTargetReference("Host/\(scheme)"), buildTypes: [.testing]),
                    ]),
                    test: Scheme.Test(
                        targets: [Scheme.Test.TestTarget(stringLiteral: Constants.testProjectName)],
                        environmentVariables: [
                            .init(variable: "OPEN_AI_KEY", value: openAIKey, enabled: true),
                            .init(variable: "LOG_FILE", value: logFile, enabled: true),
                        ]
                    )
                ),
            ],
            projectReferences: [
                ProjectReference(name: "Host", path: projectPath),
                ProjectReference(name: "QAVinci", path: "/Users/flaviocaetano/projects/QAVinci/QAVinci.xcodeproj"), // TODO: use package instead
            ]
        )
    }

    func generate() throws {
        try? FileManager.default.createDirectory(atPath: testsPath, withIntermediateDirectories: true)

        logger.debug("Writing .xcodeproj to \(project.defaultProjectPath)")
        try FileWriter(project: project).writePlists()
        let xcodeProj = try ProjectGenerator(project: project).generateXcodeProject(userName: "$USER")
        try xcodeProj.write(path: project.defaultProjectPath)
    }
}

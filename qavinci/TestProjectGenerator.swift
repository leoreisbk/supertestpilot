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

struct TestProjectGenerator {
    let testsPath: String

    let project: Project

    var testProjectPath: String {
        project.defaultProjectPath.string
    }

    init(testedProjectPath: URL, testsPath: URL) throws {
        let projectPath = testedProjectPath.path(percentEncoded: false)
        self.testsPath = testsPath.appending(component: Constants.testProjectDir).path(percentEncoded: false)

        let existingProject = try XcodeProj(pathString: projectPath)
        guard let scheme = existingProject.sharedData?.schemes.first?.name else {
            throw ErrorCases.missingScheme
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
                    info: Plist(path: self.testsPath.appendingPathComponent("Info.plist"))
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
                            // TODO
                            XCScheme.EnvironmentVariable(
                                variable: "OPEN_AI_KEY",
                                value: "foobar",
                                enabled: true
                            ),
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

        try FileWriter(project: project).writePlists()
        let xcodeProj = try ProjectGenerator(project: project).generateXcodeProject(userName: "$USER")
        try xcodeProj.write(path: project.defaultProjectPath)
    }
}

extension TestProjectGenerator {
    enum ErrorCases: Error {
        case missingScheme
    }
}

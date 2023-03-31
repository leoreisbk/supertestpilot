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
import Version

private let logger = Logger(label: #file.lastPathComponent)
struct TestProjectGenerator {
    let project: Project

    var testProjectPath: String {
        project.defaultProjectPath.string
    }

    init(
        targetDir: URL,
        openAIKey: String,
        logFile: String
    ) throws {
        logger.debug("Initializing project on \(targetDir)")

        let swiftFile = """
        import SwiftUI

        @main
        struct DummyApp: App {
            var body: some Scene {
                WindowGroup {
                    Text("")
                }
            }
        }
        """

        try? FileManager.default.createDirectory(at: targetDir.appendingPathComponent("DummyApp/"), withIntermediateDirectories: true)
        let codePath = targetDir.appendingPathComponent("DummyApp/DummyApp.swift")
        do {
            try swiftFile.write(to: codePath, atomically: true, encoding: .utf8)
        } catch {
            print(error)
        }

        self.project = try Project(
            basePath: Path(targetDir.path(percentEncoded: false)),
            name: Constants.testProjectName,
            targets: [
                Target(
                    name: "DummyApp",
                    type: .application,
                    platform: .iOS,
                    settings: Settings(
                        dictionary: [
                            "PRODUCT_BUNDLE_IDENTIFIER": "co.work.qavinci.DummyApp",
                            "DEVELOPMENT_TEAM": "KYVD9R48"
                        ]
                    ),
                    sources: [
                        TargetSource(
                            path: targetDir.path(percentEncoded: false),
                            includes: ["DummyApp/DummyApp.swift"],
                            createIntermediateGroups: true
                        ),
                    ],
                    info: .init(
                        path: "Info.plist"
                    )
                ),
                Target(
                    name: Constants.testProjectName,
                    type: .uiTestBundle,
                    platform: .iOS,
                    deploymentTarget: Version("15.0"),
                    sources: [
                        TargetSource(
                            path: targetDir.path(percentEncoded: false),
                            includes: ["*.swift"],
                            createIntermediateGroups: true
                        ),
                    ],
                    dependencies: [
                        Dependency(type: .target, reference: "DummyApp"),
                        Dependency(type: .package(product: "QAVinciKit"), reference: "QAVinciKit"),
                    ],
                    info: Plist(path: "Info.plist")
                ),
            ],
            schemes: [
                Scheme(
                    name: Constants.testProjectName,
                    build: Scheme.Build(targets: [
                        Scheme.BuildTarget(target: TestableTargetReference("DummyApp"), buildTypes: [.testing]),
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
            packages: [
                "QAVinciKit": .remote(url: "git@github.com:workco/qavinci-poc.git", versionRequirement: .branch("main")), // TODO: rename repo & use HTTPS endpoint instead of SSH
                
            ]
        )
    }

    func generate() throws {
        logger.debug("Writing .xcodeproj to \(project.defaultProjectPath)")
        try FileWriter(project: project).writePlists()
        let xcodeProj = try ProjectGenerator(project: project).generateXcodeProject(userName: "$USER")
        try xcodeProj.write(path: project.defaultProjectPath)
    }
}

private extension XcodeProj {
    func getRunnableScheme(named scheme: String?) throws -> String {
        let schemeNames = sharedData?.schemes
            .filter { $0.launchAction?.runnable != nil }
            .map { $0.name }

        logger.debug("Schemes found in the given project: \(schemeNames?.description ?? "None")")

        if let scheme = scheme {
            guard schemeNames?.contains(scheme) == true else {
                throw ValidationError("Scheme '\(scheme)' was not found in the project")
            }

            return scheme
        }

        guard schemeNames?.isEmpty == false else {
            throw ValidationError("Couldn't find any schemes available in the given project")
        }

        guard schemeNames?.count == 1 else {
            throw ValidationError("Project has multiple runnable schemes. Please specify with the --scheme option")
        }

        return schemeNames![0]
    }
}

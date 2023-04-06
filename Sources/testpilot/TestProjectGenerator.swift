//
//  TestProjectGenerator.swift
//  testpilot
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
        loggingAddress: String,
        loggingServerURL: URL,
        codeSignJSON: URL? = nil
    ) throws {
        logger.debug("Initializing project on \(targetDir)")
        
        let codeSignSettings: ProjectSpec.Settings
        if let codeSignJSON = codeSignJSON {
            let codeSign = try CodeSign.from(file: codeSignJSON)
            codeSignSettings = .init(dictionary: [
                "DEVELOPMENT_TEAM": codeSign.teamId,
                "PRODUCT_BUNDLE_IDENTIFIER": codeSign.runnerBundleId,
                "PROVISIONING_PROFILE_SPECIFIER": codeSign.provisioningProfile,
                "CODE_SIGN_STYLE": codeSign.codeSignStyle,
                "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
                "SUPPORTS_MACCATALYST": "NO"
            ])
        } else {
            codeSignSettings = .init(dictionary: [
                "PRODUCT_BUNDLE_IDENTIFIER": "co.work.TestPilot.UIRunner",
                "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
                "SUPPORTS_MACCATALYST": "NO"
            ])
        }

        self.project = try Project(
            basePath: Path(targetDir.path(percentEncoded: false)),
            name: Constants.testProjectName,
            targets: [
                Target(
                    name: Constants.testProjectName,
                    type: .uiTestBundle,
                    platform: .iOS,
                    deploymentTarget: Version("15.0"),
                    settings: codeSignSettings,
                    sources: [
                        TargetSource(
                            path: targetDir.path(percentEncoded: false),
                            includes: ["*.swift"],
                            createIntermediateGroups: true
                        ),
                    ],
                    dependencies: [
                        Dependency(type: .package(product: "TestPilotKit"), reference: "TestPilotKit"),
                    ],
                    info: Plist(path: "Info.plist")
                ),
            ],
            schemes: [
                Scheme(
                    name: Constants.testProjectName,
                    build: Scheme.Build(targets: [
                        Scheme.BuildTarget(target: TestableTargetReference(Constants.testProjectName), buildTypes: [.testing]),
                    ]),
                    test: Scheme.Test(
                        targets: [Scheme.Test.TestTarget(stringLiteral: Constants.testProjectName)],
                        environmentVariables: [
                            .init(variable: "OPEN_AI_KEY", value: openAIKey, enabled: true),
                            .init(variable: "WS_RECEIVER", value: loggingAddress, enabled: true),
                            .init(variable: "WS_SERVER", value: loggingServerURL.absoluteString, enabled: true),
                        ]
                    )
                ),
            ],
            packages: [
                "TestPilotKit": .remote(url: "git@github.com:workco/TestPilot.git", versionRequirement: .branch("main")), // TODO: rename repo & use HTTPS endpoint instead of SSH
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

private extension TestProjectGenerator {
    struct CodeSign: Decodable {
        let teamId: String
        let runnerBundleId: String
        let provisioningProfile: String
        let codeSignStyle: String
        
        static func from(file: URL) throws -> Self {
            let jsonData = try Data(contentsOf: file)
            return try JSONDecoder().decode(Self.self, from: jsonData)
        }
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

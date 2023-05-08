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

private let useLocalKMMSDK = true
private let logger = Logger(label: #file.lastPathComponent)
struct TestProjectGenerator {
    static let runnerDeploymentVersion = Version("15.0")

    let project: Project

    var testProjectPath: String {
        project.defaultProjectPath.string
    }
    
    private static func testPilotKitPackage(_ testpilotKitPath: String?) -> SwiftPackage {
        if (useLocalKMMSDK) {
            let localSourcePath = Path(URL(filePath: #file).deletingLastPathComponent().path())
            let localPackagePath = Path(components: [localSourcePath.string, "../../sdk/swift-wrapper"])
            return .local(path: localPackagePath.absolute().string, group: nil)
        } else if let testpilotKitPath = testpilotKitPath {
            return .local(path: testpilotKitPath, group: nil)
        } else {
            return .remote(url: "https://fjcaetano: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@github.com/workco/TestPilot.git", versionRequirement: .branch("main")) // TODO: rename repo & use HTTPS endpoint instead of SSH
        }
    }

    init(
        targetDir: URL,
        openAIKey: String,
        openAIOrg: String? = nil,
        openAIHost: String? = nil,
        openAIHeaders: [String: String] = [:],
        loggingAddress: String,
        loggingServerURL: URL,
        teamID: String? = nil,
        bundleID: String? = nil,
        provisioningProfile: String? = nil,
        testpilotKitPath: String? = nil
    ) throws {
        logger.debug("Initializing project on \(targetDir)")
        
        let codeSignSettings: ProjectSpec.Settings
        if let teamID = teamID, let bundleID = bundleID, let provisioningProfile = provisioningProfile {
            codeSignSettings = .init(dictionary: [
                "DEVELOPMENT_TEAM": teamID,
                "PRODUCT_BUNDLE_IDENTIFIER": bundleID,
                "PROVISIONING_PROFILE_SPECIFIER": provisioningProfile,
                "CODE_SIGN_STYLE": "Manual",
                "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
                "SUPPORTS_MACCATALYST": "NO"
            ])
        } else {
            codeSignSettings = .init(dictionary: [
                "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
                "SUPPORTS_MACCATALYST": "NO"
            ])
        }
        
        var optionalEnvs = [XCScheme.EnvironmentVariable]()
        if let openAIOrg = openAIOrg {
            optionalEnvs.append(.init(variable: "OPEN_AI_ORG", value: openAIOrg, enabled: true))
        }
        if let openAIHost = openAIHost {
            optionalEnvs.append(.init(variable: "OPEN_AI_HOST", value: openAIHost, enabled: true))
        }
        if openAIHeaders.count > 0 {
            // Encode headers into a single string where keys and their respective values are separated by a ":"
            // where multiple entries will be separated by a ";"
            let headersEnv = openAIHeaders
                .map { (key, value) in
                    let escapedValue = value.replacingOccurrences(of: ";", with: "\\;")
                    return "\(key):\(escapedValue)"
                }
                .joined(separator: ";")
            
            optionalEnvs.append(.init(variable: "OPEN_AI_HEADERS", value: headersEnv, enabled: true))
        }
        
        self.project = try Project(
            basePath: Path(targetDir.path(percentEncoded: false)),
            name: Constants.testProjectName,
            targets: [
                Target(
                    name: Constants.testProjectName,
                    type: .uiTestBundle,
                    platform: .iOS,
                    deploymentTarget: Self.runnerDeploymentVersion,
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
                        ] + optionalEnvs
                    )
                ),
            ],
            packages: [
                "TestPilotKit": Self.testPilotKitPackage(testpilotKitPath)
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

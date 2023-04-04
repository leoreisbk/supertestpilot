//
//  Constants.swift
//  testpilot
//
//  Created by Flávio Caetano on 3/17/23.
//

import Foundation

enum Constants {
    static let testProjectName = "TestPilot"
    static let testFileExt = "testpilot"

    func getTestProjectURL(forProject project: String) -> URL {
        FileManager.default.temporaryDirectory.appending(component: project.deletingPathExtension)
    }

    static var tempDir: URL {
        FileManager.default.temporaryDirectory
            .appending(component: Constants.testFileExt)
    }

    static let logFilePath: String = {
        tempDir
            .appending(component: "\(ISO8601DateFormatter().string(from: Date())).log")
            .path(percentEncoded: false)
    }()
}

//
//  Constants.swift
//  qavinci
//
//  Created by Flávio Caetano on 3/17/23.
//

import Foundation

enum Constants {
    static let testProjectName = "UI Tester"
    static let testProjectDir = ".qavinci" // TODO: don't create generated files in the tests dir
    static let testFileExt = "qavinci"

    func getTestProjectURL(forProject project: String) -> URL {
        FileManager.default.temporaryDirectory.appending(component: project.deletingPathExtension)
    }

    static let logFilePath: String = {
        FileManager.default.temporaryDirectory
            .appending(component: Constants.testFileExt)
            .appending(component: "\(ISO8601DateFormatter().string(from: Date())).log")
            .path(percentEncoded: false)
    }()
}

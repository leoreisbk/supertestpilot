//
//  main.swift
//  qavinci
//
//  Created by Flávio Caetano on 3/16/23.
//

import Foundation
import ArgumentParser
import Logging

private let logger = Logger(label: #file.lastPathComponent)
struct TestFileBuilder {
    let workDir: QAVinciCommand.WorkDir
    let fileName: String

    func buildTestFile() throws {
        guard let enumerator = FileManager.default.enumerator(
            at: workDir.dirPath,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ValidationError("Couldn't find any .\(Constants.testFileExt) files in the given directory")
        }

        var files = try enumerator
            .compactMap { $0 as? URL }
            .filter {
                try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                && $0.pathExtension == Constants.testFileExt
            }

        if let testCase = workDir.testCase {
            files = files.filter { $0.path(percentEncoded: false).hasSuffix(testCase) }
        }

        logger.info("""

        Found \(files.count) test files:
        \(
            files.enumerated().map { idx, url in
                "\(idx + 1). \(url.lastPathComponent.deletingPathExtension.sentence)"
            }
            .joined(separator: "\n")
        )

        """)

        let tests = try files
            .map { url in
                try makeTestCase(title: url.deletingPathExtension().lastPathComponent, objective: String(contentsOf: url))
            }

        guard !tests.isEmpty else {
            throw ValidationError("Couldn't find any .\(Constants.testFileExt) files in the given directory")
        }

        let testFile = """
        import XCTest
        import QAVinciKit

        final class TestApp: XCTestCase {
        \(tests.joined(separator: "\n\n"))
        }
        """

        let testPath = workDir.dirPath.appending(component: "\(Constants.testProjectDir)/\(fileName)")
        logger.debug("Writing test cases to \(testPath)")
        try? FileManager.default.createDirectory(at: testPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try testFile.write(to: testPath, atomically: true, encoding: .utf8)
    }

    private func makeTestCase(title: String, objective: String) -> String {
        """
            func test\(title.capitalizedSentence)() async throws {
                Logging.info("\\nStarting test: '\(title.capitalizedSentence.sentence)'")
                try await automate(
                    objective: \"""
                    \(objective)
                    \"""
                )
                Logging.info("✅ Done!")
            }
        """
    }
}

extension String {
    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }

    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }

    func appendingPathComponent(_ component: String) -> String {
        (self as NSString).appendingPathComponent(component)
    }

    var capitalizedSentence: String {
        let firstLetter = prefix(1).capitalized
        return firstLetter + dropFirst()
    }

    var sentence: String {
        replacing(/([a-z])([A-Z])/, with: { "\($0.output.1) \($0.output.2)"})
            .capitalized
    }

    var deletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }
}

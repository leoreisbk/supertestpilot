//
//  main.swift
//  qavinci
//
//  Created by Flávio Caetano on 3/16/23.
//

import Foundation
import ArgumentParser

struct TestFileBuilder {
    let path: URL
    let fileName: String

    init(path: URL, fileName: String = "Test.swift") {
        self.path = path
        self.fileName = fileName
    }

    func buildTestFile() throws {
        guard let enumerator = FileManager.default.enumerator(
            at: path,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ErrorCase.noTestFiles
        }

        let files = try enumerator
            .compactMap { $0 as? URL }
            .filter {
                try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                && $0.pathExtension == Constants.testFileExt
            }

        let tests = try files
            .map { url in
                try makeTestCase(title: url.deletingPathExtension().lastPathComponent, objective: String(contentsOf: url))
            }

        guard !tests.isEmpty else {
            throw ErrorCase.noTestFiles
        }

        let testFile = """
        import XCTest
        import QAVinciKit

        final class TestApp: XCTestCase {
        \(tests.joined(separator: "\n\n"))
        }
        """

        let testPath = path.appending(component: "\(Constants.testProjectDir)/\(fileName)")
        try? FileManager.default.createDirectory(at: testPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try testFile.write(to: testPath, atomically: true, encoding: .utf8)
    }

    private func makeTestCase(title: String, objective: String) -> String {
        """
            func test\(title.capitalizedSentence)() async {
                await automate(
                    objective: \"""
                    \(objective)
                    \"""
                )
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

    var deletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }
}

extension TestFileBuilder {
    enum ErrorCase: Error, CustomStringConvertible {
        case noTestFiles

        var description: String {
            "Couldn't find any .\(Constants.testFileExt) files in the given directory"
        }
    }
}

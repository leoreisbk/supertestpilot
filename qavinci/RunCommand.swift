//
//  RunCommand.swift
//  qavinci
//
//  Created by Flávio Caetano on 3/17/23.
//

import Foundation

struct Runner {
    let testProjectPath: String
    let launchSimulator: Bool

    private let xcodePath: URL

    init(testProjectPath: String, launchSimulator: Bool) throws {
        self.testProjectPath = testProjectPath
        self.launchSimulator = launchSimulator
        self.xcodePath = try Self.getXcodePath()
    }

    func run() throws {
        // TODO: find highest device
        guard let uuid = try findDeviceUUID(name: "iPhone 14 Pro") else {
            return
        }

        if launchSimulator {
            try launchSimulator(uuid: uuid)
        }

        try runTests(uuid: uuid)
    }

    private func runTests(uuid: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcodebuild")
       process.standardError = FileHandle.nullDevice
        process.arguments = [
            "-quiet",
            "-project", testProjectPath,
            "-scheme", Constants.testProjectName,
            "-sdk", "iphonesimulator",
            "-destination", "platform=iOS Simulator,id=\(uuid)",
            "test"
        ]

        try ProcessPool.shared.run(process: process)
        process.waitUntilExit()
    }

    private func launchSimulator(uuid: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = ["-a", "Simulator", "--args", "-CurrentDeviceUDID", uuid]

        try ProcessPool.shared.run(process: process)
    }

    private func findDeviceUUID(name: String) throws -> String? {
        let output = Pipe()
        let process = Process()
        process.executableURL = xcodePath.appending(component: "usr/bin/simctl")
        process.standardOutput = output
        process.arguments = ["list", "devices", name, "-j"]

        try ProcessPool.shared.run(process: process)
        process.waitUntilExit()

        guard let data = try output.fileHandleForReading.readToEnd() else {
            return nil
        }

        let simulators = try JSONDecoder().decode(Simulators.self, from: data)
        return simulators.devices
            .sorted { $1.key < $0.key }
            .compactMap { $0.value }
            .flatMap { $0 }
            .first(where: { ($0 as Device).name == name })?
            .udid
    }

    private static func getXcodePath() throws -> URL {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcode-select")
        process.standardOutput = output
        process.arguments = ["--print-path"]

        try ProcessPool.shared.run(process: process)
        process.waitUntilExit()

        guard let path = try output.fileHandleForReading.readToEnd()
            .flatMap({ String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) })
        else {
            throw ErrorCase.xcodeNotFound
        }

        return URL(filePath: path)
    }
}

private extension Runner {
    struct Simulators: Decodable {
        let devices: [String: [Device]]
    }

    struct Device: Decodable {
        let udid: String
        let name: String
    }

    enum ErrorCase: Error {
        case xcodeNotFound
    }
}

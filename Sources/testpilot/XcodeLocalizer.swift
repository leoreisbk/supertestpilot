import Foundation

struct Xcode {
    static func getXcodePath() throws -> URL {
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

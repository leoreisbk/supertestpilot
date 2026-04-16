// mac-app/TestPilotApp/Services/WebRunner.swift
import Foundation

private let cacheDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".testpilot")

enum WebRunnerError: LocalizedError {
    case jarNotFound
    case jreNotFound

    var errorDescription: String? {
        switch self {
        case .jarNotFound:
            return "Web runner not found. Click \"Check for Updates\" in Settings."
        case .jreNotFound:
            return "Java runtime not found. Install Java 17+ or click \"Check for Updates\" in Settings."
        }
    }
}

/// Returns the bundled JRE if it's a native macOS binary, otherwise falls back
/// to the system `java` on PATH. Throws `jreNotFound` if neither is available.
func resolveJava() throws -> URL {
    let bundled = cacheDir.appendingPathComponent("web/jre/bin/java")
    if FileManager.default.fileExists(atPath: bundled.path), isMacOSBinary(at: bundled.path) {
        return bundled
    }
    // Fall back to system Java
    let result = try? Shell.which("java")
    guard let systemJava = result, !systemJava.isEmpty else {
        throw WebRunnerError.jreNotFound
    }
    return URL(fileURLWithPath: systemJava)
}

private func isMacOSBinary(at path: String) -> Bool {
    // Read the first 4 bytes — Mach-O magic numbers: 0xFEEDFACE (32-bit) or 0xFEEDFACF (64-bit)
    // or 0xCAFEBABE (fat/universal). ELF binaries start with 0x7F454C46 and cannot run on macOS.
    guard let fh = FileHandle(forReadingAtPath: path) else { return false }
    defer { try? fh.close() }
    let magic = fh.readData(ofLength: 4)
    guard magic.count == 4 else { return false }
    let bytes = [magic[0], magic[1], magic[2], magic[3]]
    // ELF magic: 0x7F 'E' 'L' 'F'
    if bytes == [0x7F, 0x45, 0x4C, 0x46] { return false }
    return true
}

private enum Shell {
    static func which(_ command: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [command]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WebRunner {
    let config: RunConfig
    let settings: SettingsStore

    @MainActor
    func makeProcess() throws -> Process {
        let java = try resolveJava()
        let jar  = cacheDir.appendingPathComponent("web/testpilot-web.jar")
        guard FileManager.default.fileExists(atPath: jar.path) else { throw WebRunnerError.jarNotFound }

        let provider   = (config.providerOverride ?? settings.provider).rawValue
        let outputPath = NSString(string: config.outputPath).expandingTildeInPath

        var env = ProcessInfo.processInfo.environment
        env["TESTPILOT_MODE"]         = config.mode.rawValue
        env["TESTPILOT_WEB_URL"]      = config.url
        env["TESTPILOT_OBJECTIVE"]    = config.objective
        env["TESTPILOT_API_KEY"]      = settings.apiKey
        env["TESTPILOT_PROVIDER"]     = provider
        env["TESTPILOT_MAX_STEPS"]    = "\(config.maxSteps)"
        env["TESTPILOT_LANG"]         = config.language.rawValue
        env["TESTPILOT_OUTPUT"]       = outputPath
        env["TESTPILOT_WEB_USERNAME"] = config.username
        env["TESTPILOT_WEB_PASSWORD"] = config.password

        let proc = Process()
        proc.executableURL = java
        proc.arguments     = ["-jar", jar.path]
        proc.environment   = env
        return proc
    }

    @MainActor
    func makeWebLoginProcess() throws -> Process {
        let java = try resolveJava()
        let jar  = cacheDir.appendingPathComponent("web/testpilot-web.jar")
        guard FileManager.default.fileExists(atPath: jar.path) else { throw WebRunnerError.jarNotFound }

        let provider = (config.providerOverride ?? settings.provider).rawValue

        var env = ProcessInfo.processInfo.environment
        env["TESTPILOT_MODE"]     = "login"
        env["TESTPILOT_WEB_URL"]  = config.url
        env["TESTPILOT_API_KEY"]  = settings.apiKey.isEmpty ? "dummy" : settings.apiKey
        env["TESTPILOT_PROVIDER"] = provider

        let proc = Process()
        proc.executableURL = java
        proc.arguments     = ["-jar", jar.path]
        proc.environment   = env
        return proc
    }
}

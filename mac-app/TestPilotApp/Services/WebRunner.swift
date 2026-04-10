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
            return "Java runtime not found. Click \"Check for Updates\" in Settings."
        }
    }
}

struct WebRunner {
    let config: RunConfig
    let settings: SettingsStore

    @MainActor
    func makeProcess() throws -> Process {
        let jreJava = cacheDir.appendingPathComponent("web/jre/bin/java")
        let jar     = cacheDir.appendingPathComponent("web/testpilot-web.jar")

        guard FileManager.default.fileExists(atPath: jreJava.path) else {
            throw WebRunnerError.jreNotFound
        }
        guard FileManager.default.fileExists(atPath: jar.path) else {
            throw WebRunnerError.jarNotFound
        }

        let provider = (config.providerOverride ?? settings.provider).rawValue
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
        proc.executableURL = jreJava
        proc.arguments     = ["-jar", jar.path]
        proc.environment   = env
        return proc
    }

    @MainActor
    func makeWebLoginProcess() throws -> Process {
        let jreJava = cacheDir.appendingPathComponent("web/jre/bin/java")
        let jar     = cacheDir.appendingPathComponent("web/testpilot-web.jar")

        guard FileManager.default.fileExists(atPath: jreJava.path) else {
            throw WebRunnerError.jreNotFound
        }
        guard FileManager.default.fileExists(atPath: jar.path) else {
            throw WebRunnerError.jarNotFound
        }

        let provider = (config.providerOverride ?? settings.provider).rawValue

        var env = ProcessInfo.processInfo.environment
        env["TESTPILOT_MODE"]     = "login"
        env["TESTPILOT_WEB_URL"]  = config.url
        env["TESTPILOT_API_KEY"]  = settings.apiKey.isEmpty ? "dummy" : settings.apiKey
        env["TESTPILOT_PROVIDER"] = provider

        let proc = Process()
        proc.executableURL = jreJava
        proc.arguments     = ["-jar", jar.path]
        proc.environment   = env
        return proc
    }
}

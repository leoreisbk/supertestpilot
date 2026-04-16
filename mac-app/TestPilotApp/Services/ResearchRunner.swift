import Foundation

struct ResearchRunner {
    let config: RunConfig
    let settings: SettingsStore

    @MainActor
    func makeProcess() throws -> Process {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".testpilot")
        let jreJava = cacheDir.appendingPathComponent("web/jre/bin/java")
        let jar     = cacheDir.appendingPathComponent("web/testpilot-web.jar")

        guard FileManager.default.fileExists(atPath: jreJava.path) else {
            throw WebRunnerError.jreNotFound
        }
        guard FileManager.default.fileExists(atPath: jar.path) else {
            throw WebRunnerError.jarNotFound
        }

        let provider       = (config.providerOverride ?? settings.provider).rawValue
        let outputPath     = NSString(string: config.outputPath).expandingTildeInPath
        let personaContent = config.personaContent ?? ""

        var env = ProcessInfo.processInfo.environment
        env["TESTPILOT_MODE"]             = "research"
        env["TESTPILOT_API_KEY"]          = settings.apiKey
        env["TESTPILOT_PROVIDER"]         = provider
        env["TESTPILOT_MAX_STEPS"]        = "\(config.maxSteps)"
        env["TESTPILOT_LANG"]             = config.language.rawValue
        env["TESTPILOT_OUTPUT"]           = outputPath
        env["TESTPILOT_OBJECTIVE"]        = config.objective
        env["TESTPILOT_PERSONA"]          = personaContent
        env["TESTPILOT_MOBBIN_FLOW_URL"]  = config.mobbinFlowUrl
        env["TESTPILOT_MOBBIN_APP"]       = config.mobbinAppName
        env["TESTPILOT_MOBBIN_FLOW_NAME"] = config.mobbinFlowName

        let proc = Process()
        proc.executableURL = jreJava
        proc.arguments     = ["-jar", jar.path]
        proc.environment   = env
        return proc
    }

    @MainActor
    func makeMobbinLoginProcess() throws -> Process {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".testpilot")
        let jreJava = cacheDir.appendingPathComponent("web/jre/bin/java")
        let jar     = cacheDir.appendingPathComponent("web/testpilot-web.jar")

        guard FileManager.default.fileExists(atPath: jreJava.path) else {
            throw WebRunnerError.jreNotFound
        }
        guard FileManager.default.fileExists(atPath: jar.path) else {
            throw WebRunnerError.jarNotFound
        }

        var env = ProcessInfo.processInfo.environment
        env["TESTPILOT_MODE"]    = "mobbin-login"
        env["TESTPILOT_API_KEY"] = settings.apiKey.isEmpty ? "dummy" : settings.apiKey

        let proc = Process()
        proc.executableURL = jreJava
        proc.arguments     = ["-jar", jar.path]
        proc.environment   = env
        return proc
    }
}

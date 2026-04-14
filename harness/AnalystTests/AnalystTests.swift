// This file is overwritten by TestPilot before each run. Do not edit manually.
// This placeholder matches the format generated at runtime — kept in sync for
// Xcode development and contributor reference. CI excludes this file from the
// packaged artifact (see release.yml: rsync --exclude).
import XCTest
import TestPilotShared

class AnalystTests: XCTestCase {
    var analyst: AnalystIOS!
    var xcApp: XCUIApplication!
    var username: String?
    var password: String?

    override func setUp() {
        super.setUp()
        xcApp = XCUIApplication()
        let provider: AIProvider = .anthropic
        let env = ProcessInfo.processInfo.environment
        let apiKey = env["TESTPILOT_API_KEY"] ?? ""
        username = env["TESTPILOT_USERNAME"].flatMap { $0.isEmpty ? nil : $0 }
        password = env["TESTPILOT_PASSWORD"].flatMap { $0.isEmpty ? nil : $0 }
        let personaB64 = env["TESTPILOT_PERSONA_B64"]
        let persona: String? = personaB64.flatMap { Data(base64Encoded: $0) }
            .flatMap { String(data: $0, encoding: .utf8) }
        let config = ConfigBuilder()
            .provider(provider: provider)
            .apiKey(key: apiKey)
            .maxSteps(steps: 40)
            .language(lang: "en")
            .persona(markdown: persona)
            .build()
        analyst = AnalystIOS(config: config)
    }

    func testAnalyze() async throws {
        let _ = try await analyst.run(
            objective: "",
            xcApp: xcApp,
            username: username,
            password: password
        )
    }
}

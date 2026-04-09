// This file is overwritten by the testpilot CLI before each run.
// Do not edit manually.
import XCTest
import TestPilotShared

class AnalystTests: XCTestCase {
    func testAnalyze() async throws {
        let env = ProcessInfo.processInfo.environment
        let providerStr = env["TESTPILOT_PROVIDER"] ?? "anthropic"
        let provider: AIProvider = providerStr == "openai" ? .openai : .anthropic
        let maxSteps = Int32(env["TESTPILOT_MAX_STEPS"].flatMap(Int.init) ?? 20)
        let config = ConfigBuilder()
            .provider(provider: provider)
            .apiKey(key: env["TESTPILOT_API_KEY"] ?? "")
            .maxSteps(steps: maxSteps)
            .build()
        let analyst = AnalystIOS(config: config)
        let _ = try await analyst.run(
            objective: env["TESTPILOT_OBJECTIVE"] ?? "",
            bundleId: env["TESTPILOT_BUNDLE_ID"]
        )
    }
}

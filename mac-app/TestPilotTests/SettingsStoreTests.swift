import XCTest
@testable import TestPilotApp

final class SettingsStoreTests: XCTestCase {
    func testParseEnvStringExtractsProvider() {
        let raw = "TESTPILOT_PROVIDER=gemini\nTESTPILOT_TEAM_ID=ABC123"
        let parsed = SettingsStore.parseEnv(raw)
        XCTAssertEqual(parsed.provider, .gemini)
        XCTAssertEqual(parsed.teamId, "ABC123")
        XCTAssertNil(parsed.apiKey)
    }

    func testParseEnvStringExtractsApiKey() {
        let raw = "TESTPILOT_API_KEY=sk-test\nTESTPILOT_PROVIDER=openai"
        let parsed = SettingsStore.parseEnv(raw)
        XCTAssertEqual(parsed.apiKey, "sk-test")
        XCTAssertEqual(parsed.provider, .openai)
    }

    func testBuildEnvStringRoundTrip() {
        let raw = SettingsStore.buildEnv(apiKey: "my-key", provider: .anthropic, teamId: "T99")
        let parsed = SettingsStore.parseEnv(raw)
        XCTAssertEqual(parsed.apiKey, "my-key")
        XCTAssertEqual(parsed.provider, .anthropic)
        XCTAssertEqual(parsed.teamId, "T99")
    }

    func testParseEnvIgnoresUnknownKeys() {
        let raw = "SOME_OTHER_VAR=foo\nTESTPILOT_PROVIDER=anthropic"
        let parsed = SettingsStore.parseEnv(raw)
        XCTAssertEqual(parsed.provider, .anthropic)
    }
}

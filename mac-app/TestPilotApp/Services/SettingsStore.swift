import Foundation
import Security
import Observation

@Observable
final class SettingsStore {
    var provider: AIProvider = .anthropic
    var teamId: String = ""

    private let keychainService = "com.workco.testpilot"
    private let keychainAccount = "api-key"
    private let providerKey = "tp_provider"
    private let teamIdKey = "tp_teamId"

    private var envFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".testpilot/.env")
    }

    // MARK: - API Key (Keychain)

    var apiKey: String {
        get { keychainLoad() ?? "" }
        set { keychainSave(newValue) }
    }

    // MARK: - Raw .env (bidirectional sync)

    var rawEnv: String {
        get { SettingsStore.buildEnv(apiKey: apiKey, provider: provider, teamId: teamId) }
        set {
            let parsed = SettingsStore.parseEnv(newValue)
            if let k = parsed.apiKey { apiKey = k }
            if let p = parsed.provider { provider = p }
            if let t = parsed.teamId { teamId = t }
        }
    }

    // MARK: - Init

    init() {
        provider = {
            guard let raw = UserDefaults.standard.string(forKey: "tp_provider"),
                  let p = AIProvider(rawValue: raw) else { return .anthropic }
            return p
        }()
        teamId = UserDefaults.standard.string(forKey: "tp_teamId") ?? ""
        // Bootstrap from .env if it exists and we have no saved provider yet
        if let contents = try? String(contentsOf: envFileURL) {
            let parsed = SettingsStore.parseEnv(contents)
            if let k = parsed.apiKey, apiKey.isEmpty { apiKey = k }
            if let p = parsed.provider { provider = p }
            if let t = parsed.teamId, teamId.isEmpty { teamId = t }
        }
    }

    // MARK: - Persist

    func save() {
        UserDefaults.standard.set(provider.rawValue, forKey: providerKey)
        UserDefaults.standard.set(teamId, forKey: teamIdKey)
        writeEnvFile()
    }

    private func writeEnvFile() {
        let dir = envFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? rawEnv.write(to: envFileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Static helpers (testable)

    struct ParsedEnv {
        var apiKey: String?
        var provider: AIProvider?
        var teamId: String?
    }

    static func parseEnv(_ raw: String) -> ParsedEnv {
        var result = ParsedEnv()
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "TESTPILOT_API_KEY":  result.apiKey = value
            case "TESTPILOT_PROVIDER": result.provider = AIProvider(rawValue: value)
            case "TESTPILOT_TEAM_ID":  result.teamId = value
            default: break
            }
        }
        return result
    }

    static func buildEnv(apiKey: String, provider: AIProvider, teamId: String) -> String {
        var lines: [String] = []
        if !apiKey.isEmpty  { lines.append("TESTPILOT_API_KEY=\(apiKey)") }
        lines.append("TESTPILOT_PROVIDER=\(provider.rawValue)")
        if !teamId.isEmpty  { lines.append("TESTPILOT_TEAM_ID=\(teamId)") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Keychain

    private func keychainLoad() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainSave(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}

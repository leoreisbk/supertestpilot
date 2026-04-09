import Foundation
import Observation

enum Platform: String, Codable, CaseIterable, Identifiable {
    case ios = "ios"
    case android = "android"
    var id: String { rawValue }
    var displayName: String { self == .ios ? "iOS" : "Android" }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case anthropic, openai, gemini
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum Language: String, CaseIterable, Identifiable {
    case en
    case ptBR = "pt-BR"
    var id: String { rawValue }
    var displayName: String { self == .en ? "English" : "Português (BR)" }
}

enum RunMode: String, Codable, CaseIterable, Identifiable {
    case analyze
    case test
    var id: String { rawValue }
    var displayName: String { self == .analyze ? "Analyze" : "Test" }
}

struct RunParameter: Identifiable {
    let id = UUID()
    var key: String = ""
    var value: String = ""
    /// True when the key looks like a secret — renders a SecureField.
    var isSecret: Bool {
        let k = key.lowercased()
        return k.contains("password") || k.contains("secret") || k.contains("token")
    }
}

@Observable
final class RunConfig {
    var platform: Platform = .ios
    var selectedDevice: DeviceInfo? = nil
    var appName: String = ""
    var objective: String = ""
    var language: Language = .en
    var maxSteps: Int = 20
    // Note: tilde is expanded by AnalysisRunner via NSString.expandingTildeInPath
    var outputPath: String = "~/Desktop/report.html"
    var providerOverride: AIProvider? = nil
    var parameters: [RunParameter] = []
    var mode: RunMode = .analyze

    var isValid: Bool {
        selectedDevice != nil
            && !appName.trimmingCharacters(in: .whitespaces).isEmpty
            && !objective.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

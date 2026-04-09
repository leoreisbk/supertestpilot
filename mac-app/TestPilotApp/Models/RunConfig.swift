import Foundation
import Observation

enum Platform: String, Codable, CaseIterable, Identifiable {
    case ios = "ios"
    case android = "android"
    case web = "web"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ios:     return "iOS"
        case .android: return "Android"
        case .web:     return "Web"
        }
    }
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
    var url: String = ""
    var username: String = ""
    var password: String = ""
    var objective: String = ""
    var language: Language = .en
    var maxSteps: Int = 20
    // Note: tilde is expanded by AnalysisRunner via NSString.expandingTildeInPath
    var outputPath: String = "~/Desktop/report.html"
    var providerOverride: AIProvider? = nil
    var parameters: [RunParameter] = []
    var mode: RunMode = .analyze

    var isValid: Bool {
        guard !objective.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if platform == .web {
            return !url.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return selectedDevice != nil
            && !appName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

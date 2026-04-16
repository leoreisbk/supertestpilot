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

@Observable
final class RunConfig {
    var platform: Platform = .ios
    var selectedDevice: DeviceInfo? = nil
    var appName: String = ""
    var bundleId: String = ""
    var url: String = ""
    var username: String = ""
    var password: String = ""
    var objective: String = ""
    var language: Language = .en
    var maxSteps: Int = 40
    // Note: tilde is expanded by AnalysisRunner via NSString.expandingTildeInPath
    var outputPath: String = "~/Desktop/report.html"
    var personaPath: String = ""

    /// Returns the persona markdown content, or nil if no persona is set.
    var personaContent: String? {
        guard !personaPath.isEmpty else { return nil }
        let expanded = NSString(string: personaPath).expandingTildeInPath
        return try? String(contentsOfFile: expanded, encoding: .utf8)
    }
    var providerOverride: AIProvider? = nil
    var mode: RunMode = .analyze

    var isValid: Bool {
        let objectiveRequired = mode == .test || personaPath.isEmpty
        if objectiveRequired && objective.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if platform == .web {
            let trimmed = url.trimmingCharacters(in: .whitespaces).lowercased()
            return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
        }
        return selectedDevice != nil
            && (!appName.trimmingCharacters(in: .whitespaces).isEmpty
                || !bundleId.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

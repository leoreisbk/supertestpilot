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
    case research
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .analyze:  return "Analyze"
        case .test:     return "Test"
        case .research: return "Research"
        }
    }
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
    var mobbinURL: String = ""          // Mobbin URL or plain app name
    var mobbinDescription: String = ""
    var mobbinLimit: Int = 5

    /// App name resolved from Mobbin URL slug, or the raw mobbinURL value if not a URL.
    var mobbinAppName: String { parsedMobbinApp?.appName ?? mobbinURL }

    /// Platform resolved from Mobbin URL slug ("ios"/"android"/"web"), or derived from config.platform.
    var resolvedMobbinPlatform: String { parsedMobbinApp?.platform ?? (platform == .web ? "web" : "ios") }

    struct MobbinAppInfo { let appName: String; let platform: String }

    var parsedMobbinApp: MobbinAppInfo? { Self.parseMobbinURL(mobbinURL) }

    private static func parseMobbinURL(_ raw: String) -> MobbinAppInfo? {
        guard let url = URL(string: raw), url.host?.contains("mobbin.com") == true else { return nil }
        let parts = url.pathComponents
        guard let idx = parts.firstIndex(of: "apps"), idx + 1 < parts.count else { return nil }
        let slug = parts[idx + 1]
        // Slug format: {app-name}-{platform}-{uuid4}
        // Strip UUID4 suffix: -{8}-{4}-{4}-{4}-{12} hex chars
        let uuidPattern = "-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        guard let uuidRange = slug.range(of: uuidPattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let withoutUUID = String(slug[..<uuidRange.lowerBound])
        for platform in ["ios", "android", "web"] {
            guard withoutUUID.hasSuffix("-\(platform)") else { continue }
            let namePart = String(withoutUUID.dropLast(platform.count + 1))
            let appName = namePart.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            return MobbinAppInfo(appName: appName, platform: platform)
        }
        return nil
    }

    /// Returns the persona markdown content, or nil if no persona is set.
    var personaContent: String? {
        guard !personaPath.isEmpty else { return nil }
        let expanded = NSString(string: personaPath).expandingTildeInPath
        return try? String(contentsOfFile: expanded, encoding: .utf8)
    }
    var providerOverride: AIProvider? = nil
    var mode: RunMode = .analyze

    var isValid: Bool {
        switch mode {
        case .analyze, .test:
            let objectiveRequired = mode == .test || personaPath.isEmpty
            if objectiveRequired && objective.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            if platform == .web {
                let trimmed = url.trimmingCharacters(in: .whitespaces).lowercased()
                return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            }
            return selectedDevice != nil
                && (!appName.trimmingCharacters(in: .whitespaces).isEmpty
                    || !bundleId.trimmingCharacters(in: .whitespaces).isEmpty)

        case .research:
            return !mobbinURL.trimmingCharacters(in: .whitespaces).isEmpty
                && !objective.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

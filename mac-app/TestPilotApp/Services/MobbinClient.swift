import Foundation

struct MobbinScreen {
    let appName: String
    let imageBase64: String
    let mediaType: String
    let mobbinURL: String?
}

enum MobbinClientError: LocalizedError {
    case sessionInitFailed(String)
    case toolCallFailed(String)
    case tokenExpired
    case noScreensFound

    var errorDescription: String? {
        switch self {
        case .sessionInitFailed(let m): return "Mobbin MCP session failed: \(m)"
        case .toolCallFailed(let m):    return "Mobbin search failed: \(m)"
        case .tokenExpired:             return "Mobbin token expired — reconnect."
        case .noScreensFound:           return "No screens found for this app on Mobbin."
        }
    }
}

final class MobbinClient {
    private static let endpoint = URL(string: "https://api.mobbin.com/mcp")!

    func searchScreens(appName: String, description: String, limit: Int, token: String) async throws -> [MobbinScreen] {
        let sessionId = try await initSession(token: token)
        let query = description.isEmpty ? appName : "\(appName) \(description)"

        let (data, http) = try await mcpPost([
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": "search_screens",
                       "arguments": ["query": query, "limit": limit] as [String: Any]]
        ], token: token, sessionId: sessionId.isEmpty ? nil : sessionId)

        if http.statusCode == 401 { throw MobbinClientError.tokenExpired }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return try parseRPCResponse(json, appName: appName)
        }
        return try parseSSE(data, appName: appName)
    }

    // MARK: - MCP session init

    private func initSession(token: String) async throws -> String {
        let (data, http) = try await mcpPost([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2024-11-05",
                       "capabilities": [:] as [String: Any],
                       "clientInfo": ["name": "testpilot", "version": "1.0"]]
        ], token: token, sessionId: nil)

        if http.statusCode == 401 { throw MobbinClientError.tokenExpired }
        guard http.statusCode == 200 else {
            throw MobbinClientError.sessionInitFailed("HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }

        let sessionId = http.value(forHTTPHeaderField: "Mcp-Session-Id") ?? ""

        _ = try? await mcpPost(["jsonrpc": "2.0", "method": "notifications/initialized"],
                               token: token, sessionId: sessionId.isEmpty ? nil : sessionId)

        return sessionId
    }

    // MARK: - HTTP helper

    private func mcpPost(_ body: [String: Any], token: String, sessionId: String?) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json",                    forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)",                     forHTTPHeaderField: "Authorization")
        if let sid = sessionId { req.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw MobbinClientError.toolCallFailed("Non-HTTP response") }
        return (data, http)
    }

    // MARK: - Response parsers

    private func parseRPCResponse(_ json: [String: Any], appName: String) throws -> [MobbinScreen] {
        if let err = (json["error"] as? [String: Any])?["message"] as? String {
            throw MobbinClientError.toolCallFailed(err)
        }
        guard let result = json["result"] as? [String: Any] else {
            throw MobbinClientError.toolCallFailed("No result field")
        }
        return try parseResult(result, appName: appName)
    }

    private func parseResult(_ result: [String: Any], appName: String) throws -> [MobbinScreen] {
        guard let content = result["content"] as? [[String: Any]] else {
            throw MobbinClientError.toolCallFailed("No content field")
        }
        for item in content {
            if (item["type"] as? String) == "text", let text = item["text"] as? String {
                let screens = parseScreenArray(text, appName: appName)
                if !screens.isEmpty { return screens }
            }
        }
        throw MobbinClientError.noScreensFound
    }

    private func parseSSE(_ data: Data, appName: String) throws -> [MobbinScreen] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MobbinClientError.toolCallFailed("Invalid encoding")
        }
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("data: "),
                  let d = String(t.dropFirst(6)).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let result = json["result"] as? [String: Any]
            else { continue }
            return try parseResult(result, appName: appName)
        }
        throw MobbinClientError.toolCallFailed("Could not parse SSE response")
    }

    private func parseScreenArray(_ text: String, appName: String) -> [MobbinScreen] {
        guard let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return arr.compactMap { s -> MobbinScreen? in
            guard let img = s["image"] as? String
                         ?? s["screenshot"] as? String
                         ?? s["image_data"] as? String
                         ?? s["imageData"] as? String
            else { return nil }

            return MobbinScreen(
                appName:     s["app_name"] as? String ?? s["appName"] as? String ?? appName,
                imageBase64: img,
                mediaType:   s["media_type"] as? String ?? s["mediaType"] as? String ?? "image/jpeg",
                mobbinURL:   s["url"] as? String ?? s["mobbin_url"] as? String
            )
        }
    }
}

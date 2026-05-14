import Foundation

struct MobbinScreen {
    let appName: String
    let imageBase64: String  // base64-encoded image data
    let mediaType: String    // "image/jpeg" or "image/webp"
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

    // platform: "ios" or "web"
    func searchScreens(appName: String, description: String, limit: Int, platform: String, token: String) async throws -> [MobbinScreen] {
        let sessionId = try await initSession(token: token)
        let query = description.isEmpty ? appName : "\(appName) \(description)"

        let (data, http) = try await mcpPost([
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": "search_screens",
                       "arguments": [
                           "query": query,
                           "platform": platform,
                           "limit": limit,
                           "mode": "fast",
                           "image_format": "jpg"
                       ] as [String: Any]]
        ], token: token, sessionId: sessionId.isEmpty ? nil : sessionId)

        if http.statusCode == 401 { throw MobbinClientError.tokenExpired }

        // Server always responds with SSE; try plain JSON first as a fallback
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return try parseRPCResult(json, appName: appName)
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
        req.timeoutInterval = 300

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw MobbinClientError.toolCallFailed("Non-HTTP response") }
        return (data, http)
    }

    // MARK: - Response parsers

    // Mobbin returns SSE: event: message\ndata: <json>\n\n
    // The JSON result.content array has:
    //   [0] { "type": "text", "text": "{\"screens\":[{index, id, image_url, mobbin_url, app_name, platform}]}" }
    //   [1..N] { "type": "image", "data": "<base64>", "mimeType": "image/jpeg" }
    // Images correspond to screens by index order.

    private func parseSSE(_ data: Data, appName: String) throws -> [MobbinScreen] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MobbinClientError.toolCallFailed("Invalid encoding")
        }
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("data: "),
                  let d = String(t.dropFirst(6)).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else { continue }
            return try parseRPCResult(json, appName: appName)
        }
        throw MobbinClientError.toolCallFailed("Could not parse SSE response")
    }

    private func parseRPCResult(_ json: [String: Any], appName: String) throws -> [MobbinScreen] {
        if let err = (json["error"] as? [String: Any])?["message"] as? String {
            throw MobbinClientError.toolCallFailed(err)
        }
        guard let result = json["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]] else {
            throw MobbinClientError.toolCallFailed("Unexpected response shape")
        }

        // Check for tool-level error (isError: true)
        if let isError = result["isError"] as? Bool, isError {
            let msg = content.first(where: { $0["type"] as? String == "text" }).flatMap { $0["text"] as? String } ?? "Tool error"
            throw MobbinClientError.toolCallFailed(msg)
        }

        // Extract metadata from the first text item
        var metaScreens: [[String: Any]] = []
        if let textItem = content.first(where: { $0["type"] as? String == "text" }),
           let textStr = textItem["text"] as? String,
           let textData = textStr.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: textData) as? [String: Any],
           let screens = parsed["screens"] as? [[String: Any]] {
            metaScreens = screens
        }

        // Extract image items in order
        let imageItems = content.filter { $0["type"] as? String == "image" }

        guard !imageItems.isEmpty else {
            throw MobbinClientError.noScreensFound
        }

        return imageItems.enumerated().compactMap { i, item -> MobbinScreen? in
            guard let base64 = item["data"] as? String, !base64.isEmpty else { return nil }
            let mimeType = item["mimeType"] as? String ?? "image/jpeg"
            let meta: [String: Any] = i < metaScreens.count ? metaScreens[i] : [:]
            return MobbinScreen(
                appName:     meta["app_name"] as? String ?? appName,
                imageBase64: base64,
                mediaType:   mimeType,
                mobbinURL:   meta["mobbin_url"] as? String
            )
        }
    }
}

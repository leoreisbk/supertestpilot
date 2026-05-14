import Foundation

enum MobbinRunnerError: LocalizedError {
    case noAPIKey
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:        return "API key not set. Open Settings and add your key."
        case .apiError(let m): return "AI API error: \(m)"
        }
    }
}

// Parsed result from the AI's structured response
private struct ScreenAnalysis {
    let observation: String  // full text including [CRITICAL]/[ISSUE]/[POSITIVE]
    let badgeClass: String   // badge-critical / badge-issue / badge-positive
    let badgeLabel: String   // CRITICAL / ISSUE / POSITIVE
    let observationText: String // text after the tag
}

struct MobbinRunner {
    let config: RunConfig
    let settings: SettingsStore

    @MainActor
    func analyze(screens: [MobbinScreen], onStep: @escaping (String) -> Void) async throws -> String {
        let key = settings.apiKey
        guard !key.isEmpty else { throw MobbinRunnerError.noAPIKey }

        onStep("Analyzing \(screens.count) screens with AI…")

        let provider = config.providerOverride ?? settings.provider
        let rawAnalysis: String
        switch provider {
        case .anthropic: rawAnalysis = try await callAnthropic(screens: screens, apiKey: key)
        case .openai:    rawAnalysis = try await callOpenAI(screens: screens, apiKey: key)
        case .gemini:    rawAnalysis = try await callGemini(screens: screens, apiKey: key)
        }

        return buildHTML(screens: screens, aiResponse: rawAnalysis)
    }

    // MARK: - Analysis prompt

    @MainActor
    private func buildAnalysisPrompt() -> String {
        let persona = config.personaContent.map { "\nPERSONA: \($0)" } ?? ""
        return """
        You are a UX research assistant.
        APP: \(config.mobbinAppName)
        OBJECTIVE: \(config.objective)\(persona)

        You will receive \(config.mobbinLimit) app screen images. Analyze each one against the OBJECTIVE.

        Respond in this EXACT format — no extra text, no markdown, no HTML:

        SUMMARY
        • [cross-screen pattern 1]
        • [cross-screen pattern 2]
        • [cross-screen pattern 3]
        END_SUMMARY

        SCREEN_1
        [CRITICAL|ISSUE|POSITIVE] one sentence observation
        END_SCREEN_1

        SCREEN_2
        [CRITICAL|ISSUE|POSITIVE] one sentence observation
        END_SCREEN_2

        (continue for all screens)
        """
    }

    // MARK: - HTML builder (uses actual images from screens array)

    @MainActor
    private func buildHTML(screens: [MobbinScreen], aiResponse: String) -> String {
        let lang = config.language.rawValue
        let isPTBR = lang == "pt-BR"
        let title     = isPTBR ? "Relatório de Pesquisa TestPilot" : "TestPilot Research Report"
        let lblSum    = isPTBR ? "Resumo" : "Summary"
        let lblScreen = isPTBR ? "Telas analisadas" : "Analyzed screens"
        let lblNum    = isPTBR ? "Tela" : "Screen"

        let summary = parseSummary(from: aiResponse)
        let analyses = parseScreenAnalyses(from: aiResponse, count: screens.count)

        let persona = config.personaContent ?? ""
        let personaCard = persona.isEmpty ? "" : """
            <div class="persona-card"><div class="persona-icon">&#x1F464;</div><div>\
            <div class="persona-label">Persona</div>\
            <div class="persona-text">\(escapeHTML(persona))</div></div></div>
            """

        var screenCards = ""
        for (i, screen) in screens.enumerated() {
            let analysis = i < analyses.count ? analyses[i] : ScreenAnalysis(observation: "", badgeClass: "badge-issue", badgeLabel: "ISSUE", observationText: "—")
            let title2 = screen.mobbinURL.map { "<a href=\"\($0)\" target=\"_blank\">\(lblNum) \(i+1)</a>" } ?? "\(lblNum) \(i+1)"
            let imgTag = "<img src=\"data:\(screen.mediaType);base64,\(screen.imageBase64)\" loading=\"lazy\"/>"
            screenCards += """
            <div class="step">
              <div class="step-header">
                <span class="step-num">\(title2)</span>
                <span class="action">\(escapeHTML(screen.appName))</span>
              </div>
              <div class="step-body">
                <div class="step-img-col">\(imgTag)</div>
                <div class="step-obs-col"><p><span class="badge \(analysis.badgeClass)">\(analysis.badgeLabel)</span>\(escapeHTML(analysis.observationText))</p></div>
              </div>
            </div>\n
            """
        }

        return """
        <!DOCTYPE html>
        <html lang="\(lang)">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title)</title>
        <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f5f5f7; color: #1d1d1f; line-height: 1.5; }
        .header { background: #fff; padding: 32px 40px; border-bottom: 1px solid #e5e5ea; }
        .header h1 { font-size: 22px; font-weight: 600; margin-bottom: 8px; }
        .header .objective { color: #6e6e73; font-size: 15px; }
        .meta { margin-top: 12px; font-size: 13px; color: #8e8e93; }
        .persona-card { display: flex; gap: 10px; align-items: flex-start; margin-top: 14px; background: #f2f2f7; border-radius: 8px; padding: 10px 14px; }
        .persona-icon { font-size: 20px; }
        .persona-label { font-size: 11px; color: #8e8e93; text-transform: uppercase; letter-spacing: .04em; }
        .persona-text { font-size: 13px; font-weight: 500; }
        .summary-box { margin: 24px 40px; background: #fff; border-radius: 12px; padding: 20px 24px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
        .summary-box h2 { font-size: 15px; font-weight: 600; margin-bottom: 8px; }
        .summary-content { font-size: 14px; color: #3a3a3c; }
        .summary-content ul { padding-left: 18px; }
        .summary-content li { margin-bottom: 3px; }
        .steps { padding: 0 40px 40px; }
        .steps h2 { font-size: 15px; font-weight: 600; margin: 24px 0 12px; }
        .step { background: #fff; border-radius: 12px; margin-bottom: 16px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
        .step-header { display: flex; align-items: center; gap: 10px; padding: 12px 16px; background: #f2f2f7; border-radius: 12px 12px 0 0; }
        .step-num { font-size: 12px; color: #8e8e93; }
        .action { font-size: 13px; font-weight: 600; }
        .action a { color: #007aff; text-decoration: none; }
        .step-body { display: flex; flex-direction: row; align-items: flex-start; }
        .step-img-col { flex: 0 0 40%; padding: 12px; }
        .step-img-col img { display: block; width: 100%; height: auto; border-radius: 8px; }
        .step-obs-col { flex: 1; padding: 16px 16px 16px 8px; font-size: 14px; line-height: 1.6; color: #3a3a3c; }
        .badge { display: inline-block; font-size: 10px; font-weight: 700; letter-spacing: .06em; padding: 1px 6px; border-radius: 3px; margin-right: 6px; }
        .badge-critical { background: #ff3b30; color: #fff; }
        .badge-issue { background: #ff9500; color: #fff; }
        .badge-positive { background: #34c759; color: #fff; }
        @media (max-width: 600px) { .step-body { flex-direction: column; } .step-img-col { width: 100%; flex: none; } }
        @media (prefers-color-scheme: dark) { body { background: #1c1c1e; color: #f5f5f7; } .header { background: #2c2c2e; border-bottom-color: #3a3a3c; } .header .objective { color: #aeaeb2; } .summary-box, .step { background: #2c2c2e; } .step-header { background: #3a3a3c; } .summary-content, .step-obs-col { color: #ebebf0; } }
        </style>
        </head>
        <body>
        <div class="header">
          <h1>\(title)</h1>
          <div class="objective">\(escapeHTML(config.objective))</div>
          <div class="meta">\(escapeHTML(config.mobbinAppName))\(config.mobbinDescription.isEmpty ? "" : " · \(escapeHTML(config.mobbinDescription))")</div>
          \(personaCard)
        </div>
        <div class="summary-box">
          <h2>\(lblSum)</h2>
          <div class="summary-content"><ul>\(summary)</ul></div>
        </div>
        <div class="steps">
          <h2>\(lblScreen)</h2>
          \(screenCards)
        </div>
        </body>
        </html>
        """
    }

    // MARK: - Response parsers

    private func parseSummary(from text: String) -> String {
        guard let start = text.range(of: "SUMMARY\n"),
              let end   = text.range(of: "\nEND_SUMMARY") else {
            // Fallback: return first non-empty lines as bullet
            return text.components(separatedBy: "\n")
                .filter { $0.hasPrefix("•") || $0.hasPrefix("-") }
                .prefix(5)
                .map { "<li>\(escapeHTML(String($0.dropFirst().trimmingCharacters(in: .whitespaces))))</li>" }
                .joined()
        }
        let block = String(text[start.upperBound..<end.lowerBound])
        return block.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line -> String in
                let clean = line.hasPrefix("•") || line.hasPrefix("-")
                    ? String(line.dropFirst().trimmingCharacters(in: .whitespaces))
                    : line
                return "<li>\(escapeHTML(clean))</li>"
            }
            .joined()
    }

    private func parseScreenAnalyses(from text: String, count: Int) -> [ScreenAnalysis] {
        var results: [ScreenAnalysis] = []
        for i in 1...max(1, count) {
            let startTag = "SCREEN_\(i)\n"
            let endTag   = "\nEND_SCREEN_\(i)"
            guard let start = text.range(of: startTag),
                  let end   = text.range(of: endTag) else { continue }
            let obs = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(parseObservation(obs))
        }
        return results
    }

    private func parseObservation(_ text: String) -> ScreenAnalysis {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[CRITICAL]") {
            let obs = String(trimmed.dropFirst("[CRITICAL]".count)).trimmingCharacters(in: .whitespaces)
            return ScreenAnalysis(observation: trimmed, badgeClass: "badge-critical", badgeLabel: "CRITICAL", observationText: obs)
        } else if trimmed.hasPrefix("[ISSUE]") {
            let obs = String(trimmed.dropFirst("[ISSUE]".count)).trimmingCharacters(in: .whitespaces)
            return ScreenAnalysis(observation: trimmed, badgeClass: "badge-issue", badgeLabel: "ISSUE", observationText: obs)
        } else if trimmed.hasPrefix("[POSITIVE]") {
            let obs = String(trimmed.dropFirst("[POSITIVE]".count)).trimmingCharacters(in: .whitespaces)
            return ScreenAnalysis(observation: trimmed, badgeClass: "badge-positive", badgeLabel: "POSITIVE", observationText: obs)
        }
        return ScreenAnalysis(observation: trimmed, badgeClass: "badge-issue", badgeLabel: "NOTE", observationText: trimmed)
    }

    private func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Anthropic

    @MainActor
    private func callAnthropic(screens: [MobbinScreen], apiKey: String) async throws -> String {
        var content: [[String: Any]] = [
            ["type": "text", "text": buildAnalysisPrompt()]
        ]
        for (i, s) in screens.enumerated() {
            content.append(["type": "text", "text": "Screen \(i + 1)/\(screens.count)"])
            content.append(["type": "image", "source": [
                "type": "base64", "media_type": s.mediaType, "data": s.imageBase64
            ]])
        }

        let body: [String: Any] = [
            "model": "claude-opus-4-5-20251101",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": content]]
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 300

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw MobbinRunnerError.apiError(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr  = json["content"] as? [[String: Any]],
              let text = arr.first?["text"] as? String
        else { throw MobbinRunnerError.apiError("Unexpected response shape") }
        return text
    }

    // MARK: - OpenAI

    @MainActor
    private func callOpenAI(screens: [MobbinScreen], apiKey: String) async throws -> String {
        var parts: [[String: Any]] = [
            ["type": "text", "text": buildAnalysisPrompt()]
        ]
        for (i, s) in screens.enumerated() {
            parts.append(["type": "text", "text": "Screen \(i + 1)/\(screens.count)"])
            parts.append(["type": "image_url", "image_url": [
                "url": "data:\(s.mediaType);base64,\(s.imageBase64)"
            ]])
        }

        let body: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": parts]]
        ]

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 300

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw MobbinRunnerError.apiError(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg     = choices.first?["message"] as? [String: Any],
              let text    = msg["content"] as? String
        else { throw MobbinRunnerError.apiError("Unexpected response shape") }
        return text
    }

    // MARK: - Gemini

    @MainActor
    private func callGemini(screens: [MobbinScreen], apiKey: String) async throws -> String {
        var parts: [[String: Any]] = [
            ["text": buildAnalysisPrompt()]
        ]
        for (i, s) in screens.enumerated() {
            parts.append(["text": "Screen \(i + 1)/\(screens.count)"])
            parts.append(["inline_data": ["mime_type": s.mediaType, "data": s.imageBase64]])
        }

        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": ["maxOutputTokens": 4096]
        ]

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 300

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw MobbinRunnerError.apiError(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        guard let json       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content    = candidates.first?["content"] as? [String: Any],
              let parts2     = content["parts"] as? [[String: Any]],
              let text       = parts2.first?["text"] as? String
        else { throw MobbinRunnerError.apiError("Unexpected Gemini response shape") }
        return text
    }
}

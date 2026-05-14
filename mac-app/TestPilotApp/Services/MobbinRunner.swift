import Foundation

enum MobbinRunnerError: LocalizedError {
    case noAPIKey
    case apiError(String)
    case noHTMLInResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:            return "API key not set. Open Settings and add your key."
        case .apiError(let m):     return "AI API error: \(m)"
        case .noHTMLInResponse:    return "The AI did not return an HTML report."
        }
    }
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
        switch provider {
        case .anthropic: return try await callAnthropic(screens: screens, apiKey: key)
        case .openai:    return try await callOpenAI(screens: screens, apiKey: key)
        case .gemini:    throw MobbinRunnerError.apiError("Gemini vision not yet supported for research mode.")
        }
    }

    // MARK: - Prompts

    @MainActor
    private func buildSystemPrompt() -> String {
        let persona = config.personaContent.map { "\nPERSONA: \($0)" } ?? ""
        return """
        You are a UX research assistant.\
        \nAPP: \(config.mobbinAppName)\
        \nOBJECTIVE: \(config.objective)\(persona)

        Analyze each screen image provided. For each screen write one observation prefixed with exactly one of:
        - [CRITICAL] for severe UX problems
        - [ISSUE] for moderate UX problems
        - [POSITIVE] for good UX patterns

        After all screens, write a summary of 3-5 cross-screen patterns.

        Then produce a COMPLETE HTML report using the exact CSS and structure below.
        Output ONLY the HTML document, starting with <!DOCTYPE html> and ending with </html>.
        """
    }

    @MainActor
    private func buildHTMLTemplate() -> String {
        let lang = config.language.rawValue
        let (title, summary, screensLabel, screenLabel): (String, String, String, String) = lang == "pt-BR"
            ? ("Relatório de Pesquisa TestPilot", "Resumo", "Telas analisadas", "Tela")
            : ("TestPilot Research Report", "Summary", "Analyzed screens", "Screen")

        let persona = config.personaContent ?? ""
        let personaCard = persona.isEmpty ? "" : """
          <div class="persona-card"><div class="persona-icon">👤</div><div>\
          <div class="persona-label">Persona</div>\
          <div class="persona-text">\(persona)</div></div></div>
          """

        return """
        ## HTML format — output this structure exactly

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

        <!DOCTYPE html>
        <html lang="\(lang)">
        <head><meta charset="UTF-8"><title>\(title)</title><style><!-- CSS above --></style></head>
        <body>
        <div class="header">
          <h1>\(title)</h1>
          <div class="objective">\(config.objective)</div>
          <div class="meta">\(config.mobbinAppName)\(config.mobbinDescription.isEmpty ? "" : " · \(config.mobbinDescription)")</div>
          \(personaCard)
        </div>
        <div class="summary-box"><h2>\(summary)</h2><div class="summary-content"><!-- YOUR SUMMARY HERE --></div></div>
        <div class="steps"><h2>\(screensLabel)</h2>
        <!-- one .step per screen; badge class: badge-critical / badge-issue / badge-positive;
             embed images as data URIs: <img src="data:image/jpeg;base64,BASE64" loading="lazy"/>
             if mobbinURL available: <a href="URL">\(screenLabel) N</a>, else plain text -->
        </div>
        </body></html>
        """
    }

    // MARK: - Anthropic

    @MainActor
    private func callAnthropic(screens: [MobbinScreen], apiKey: String) async throws -> String {
        var content: [[String: Any]] = [
            ["type": "text", "text": buildSystemPrompt() + "\n\n" + buildHTMLTemplate()]
        ]
        for (i, s) in screens.enumerated() {
            content.append(["type": "text", "text": "Screen \(i + 1)/\(screens.count) — \(s.appName)"])
            content.append(["type": "image", "source": [
                "type": "base64", "media_type": s.mediaType, "data": s.imageBase64
            ]])
        }

        let body: [String: Any] = [
            "model": "claude-opus-4-5-20251101",
            "max_tokens": 8192,
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

        return extractHTML(text)
    }

    // MARK: - OpenAI

    @MainActor
    private func callOpenAI(screens: [MobbinScreen], apiKey: String) async throws -> String {
        var parts: [[String: Any]] = [
            ["type": "text", "text": buildSystemPrompt() + "\n\n" + buildHTMLTemplate()]
        ]
        for (i, s) in screens.enumerated() {
            parts.append(["type": "text", "text": "Screen \(i + 1)/\(screens.count) — \(s.appName)"])
            parts.append(["type": "image_url", "image_url": [
                "url": "data:\(s.mediaType);base64,\(s.imageBase64)"
            ]])
        }

        let body: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 8192,
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

        return extractHTML(text)
    }

    // MARK: - HTML extraction

    private func extractHTML(_ text: String) -> String {
        if let s = text.range(of: "```html\n"), let e = text.range(of: "\n```", range: s.upperBound..<text.endIndex) {
            return String(text[s.upperBound..<e.lowerBound])
        }
        if let s = text.range(of: "<!DOCTYPE html>", options: .caseInsensitive),
           let e = text.range(of: "</html>", options: [.caseInsensitive, .backwards]) {
            return String(text[s.lowerBound...e.upperBound])
        }
        return text
    }
}

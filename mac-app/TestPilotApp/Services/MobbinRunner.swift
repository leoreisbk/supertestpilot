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

private struct ScreenAnalysis {
    let observation: String
    let badgeClass: String
    let badgeLabel: String
    let observationText: String
}

struct MobbinRunner {
    let config: RunConfig
    let settings: SettingsStore

    private static let batchThreshold = 10
    private static let batchSize = 5

    // MARK: - Entry point

    @MainActor
    func analyze(screens: [MobbinScreen], onStep: @escaping (String) -> Void) async throws -> String {
        let key = settings.apiKey
        guard !key.isEmpty else { throw MobbinRunnerError.noAPIKey }
        let provider = config.providerOverride ?? settings.provider

        onStep("Analyzing \(screens.count) screens with AI…")

        if screens.count <= Self.batchThreshold {
            let prompt = buildSinglePrompt(count: screens.count)
            let raw = try await Self.callProvider(prompt: prompt, images: screens, apiKey: key, provider: provider)
            return buildHTML(screens: screens, aiResponse: raw)
        }

        return try await analyzeBatched(screens: screens, apiKey: key, provider: provider, onStep: onStep)
    }

    // MARK: - Batched path (>10 screens)

    @MainActor
    private func analyzeBatched(
        screens: [MobbinScreen],
        apiKey: String,
        provider: AIProvider,
        onStep: @escaping (String) -> Void
    ) async throws -> String {
        let batches = screens.chunked(into: Self.batchSize)
        let totalBatches = batches.count

        // Build all prompts on MainActor before spawning tasks
        let batchPrompts = batches.enumerated().map { i, batch in
            buildBatchPrompt(count: batch.count, offset: i * Self.batchSize)
        }

        onStep("Analyzing \(screens.count) screens in \(totalBatches) parallel batches…")

        // Parallel calls — pre-sized array preserves insertion order
        var rawResults = Array(repeating: "", count: totalBatches)
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for i in 0..<totalBatches {
                let prompt = batchPrompts[i]
                let batch  = batches[i]
                group.addTask {
                    let raw = try await Self.callProvider(prompt: prompt, images: batch, apiKey: apiKey, provider: provider)
                    return (i, raw)
                }
            }
            for try await (idx, raw) in group {
                rawResults[idx] = raw
                await MainActor.run { onStep("Batch \(idx + 1)/\(totalBatches) analyzed…") }
            }
        }

        // Parse all analyses in original order
        var allAnalyses: [ScreenAnalysis] = []
        for (i, raw) in rawResults.enumerated() {
            let offset = i * Self.batchSize
            let count  = batches[i].count
            allAnalyses.append(contentsOf: parseScreenAnalysesBatch(from: raw, count: count, offset: offset))
        }

        // Text-only calibration call: normalizes severity across batches + generates summary
        onStep("Calibrating severity and generating summary…")
        let calibrationPrompt = buildCalibrationPrompt(analyses: allAnalyses)
        let calibrationRaw = try await Self.callProvider(prompt: calibrationPrompt, images: [], apiKey: apiKey, provider: provider)
        let (calibrated, summary) = parseCalibrationResponse(calibrationRaw, fallback: allAnalyses)

        return buildHTMLFromParsed(screens: screens, analyses: calibrated, summary: summary)
    }

    // MARK: - Prompt builders

    @MainActor
    private func buildSinglePrompt(count: Int) -> String {
        let persona = config.personaContent.map { "\nPERSONA: \($0)" } ?? ""
        let screenBlocks = (1...max(1, count)).map { i in
            "SCREEN_\(i)\n[CRITICAL|ISSUE|POSITIVE] one sentence observation\nEND_SCREEN_\(i)"
        }.joined(separator: "\n\n")

        return """
        You are a UX research assistant.
        APP: \(config.mobbinAppName)
        OBJECTIVE: \(config.objective)\(persona)

        You will receive \(count) app screen images. Analyze each one against the OBJECTIVE.

        Respond in this EXACT format — no extra text, no markdown, no HTML:

        SUMMARY
        • [cross-screen pattern 1]
        • [cross-screen pattern 2]
        • [cross-screen pattern 3]
        END_SUMMARY

        \(screenBlocks)
        """
    }

    @MainActor
    private func buildBatchPrompt(count: Int, offset: Int) -> String {
        let persona = config.personaContent.map { "\nPERSONA: \($0)" } ?? ""
        let screenBlocks = (1...max(1, count)).map { i in
            let n = offset + i
            return "SCREEN_\(n)\n[CRITICAL|ISSUE|POSITIVE] one sentence observation\nEND_SCREEN_\(n)"
        }.joined(separator: "\n\n")

        return """
        You are a UX research assistant.
        APP: \(config.mobbinAppName)
        OBJECTIVE: \(config.objective)\(persona)

        You will receive \(count) app screen images (screens \(offset + 1)–\(offset + count) of a larger set). Analyze each one against the OBJECTIVE.

        Respond in this EXACT format — no extra text, no markdown, no HTML:

        \(screenBlocks)
        """
    }

    @MainActor
    private func buildCalibrationPrompt(analyses: [ScreenAnalysis]) -> String {
        let lines = analyses.enumerated()
            .map { i, a in "Screen \(i + 1): \(a.observation)" }
            .joined(separator: "\n")
        let calibratedBlocks = analyses.enumerated().map { i, _ in
            "CALIBRATED_\(i + 1)\n[CRITICAL|ISSUE|POSITIVE] revised one sentence observation\nEND_CALIBRATED_\(i + 1)"
        }.joined(separator: "\n\n")

        return """
        You are a UX research assistant reviewing a complete analysis of \(analyses.count) screens.
        APP: \(config.mobbinAppName)
        OBJECTIVE: \(config.objective)

        Re-calibrate these preliminary observations for consistency — CRITICAL should be reserved for only the most severe issues across all screens:

        \(lines)

        Respond in this EXACT format — no extra text, no markdown, no HTML:

        SUMMARY
        • [cross-screen pattern 1]
        • [cross-screen pattern 2]
        • [cross-screen pattern 3]
        END_SUMMARY

        \(calibratedBlocks)
        """
    }

    // MARK: - AI provider dispatch (nonisolated — runs off main actor for parallelism)

    private static func callProvider(prompt: String, images: [MobbinScreen], apiKey: String, provider: AIProvider) async throws -> String {
        switch provider {
        case .anthropic: return try await callAnthropic(prompt: prompt, images: images, apiKey: apiKey)
        case .openai:    return try await callOpenAI(prompt: prompt, images: images, apiKey: apiKey)
        case .gemini:    return try await callGemini(prompt: prompt, images: images, apiKey: apiKey)
        }
    }

    // MARK: - HTML builders

    @MainActor
    private func buildHTML(screens: [MobbinScreen], aiResponse: String) -> String {
        let summary  = parseSummary(from: aiResponse)
        let analyses = parseScreenAnalyses(from: aiResponse, count: screens.count)
        return buildHTMLFromParsed(screens: screens, analyses: analyses, summary: summary)
    }

    @MainActor
    private func buildHTMLFromParsed(screens: [MobbinScreen], analyses: [ScreenAnalysis], summary: String) -> String {
        let lang = config.language.rawValue
        let isPTBR = lang == "pt-BR"
        let title     = isPTBR ? "Relatório de Pesquisa TestPilot" : "TestPilot Research Report"
        let lblSum    = isPTBR ? "Resumo" : "Summary"
        let lblScreen = isPTBR ? "Telas analisadas" : "Analyzed screens"
        let lblNum    = isPTBR ? "Tela" : "Screen"

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
            return text.components(separatedBy: "\n")
                .filter { $0.hasPrefix("•") || $0.hasPrefix("-") }
                .prefix(5)
                .map { "<li>\(escapeHTML(String($0.dropFirst().trimmingCharacters(in: .whitespaces))))</li>" }
                .joined()
        }
        return String(text[start.upperBound..<end.lowerBound])
            .components(separatedBy: "\n")
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
        (1...max(1, count)).compactMap { i in
            extract(from: text, start: "SCREEN_\(i)\n", end: "\nEND_SCREEN_\(i)").map(parseObservation)
        }
    }

    // Parses batch results using global screen numbers (offset + 1 ... offset + count)
    private func parseScreenAnalysesBatch(from text: String, count: Int, offset: Int) -> [ScreenAnalysis] {
        (1...max(1, count)).compactMap { i in
            let n = offset + i
            return extract(from: text, start: "SCREEN_\(n)\n", end: "\nEND_SCREEN_\(n)").map(parseObservation)
        }
    }

    // Parses calibration response; falls back to original analysis per screen if AI skips a block
    private func parseCalibrationResponse(_ text: String, fallback: [ScreenAnalysis]) -> ([ScreenAnalysis], String) {
        let summary = parseSummary(from: text)
        let calibrated = fallback.enumerated().map { i, original -> ScreenAnalysis in
            extract(from: text, start: "CALIBRATED_\(i + 1)\n", end: "\nEND_CALIBRATED_\(i + 1)")
                .map(parseObservation) ?? original
        }
        return (calibrated, summary)
    }

    private func extract(from text: String, start: String, end: String) -> String? {
        guard let s = text.range(of: start), let e = text.range(of: end) else { return nil }
        return String(text[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseObservation(_ text: String) -> ScreenAnalysis {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("[CRITICAL]") {
            return ScreenAnalysis(observation: t, badgeClass: "badge-critical", badgeLabel: "CRITICAL",
                                  observationText: String(t.dropFirst("[CRITICAL]".count)).trimmingCharacters(in: .whitespaces))
        } else if t.hasPrefix("[ISSUE]") {
            return ScreenAnalysis(observation: t, badgeClass: "badge-issue", badgeLabel: "ISSUE",
                                  observationText: String(t.dropFirst("[ISSUE]".count)).trimmingCharacters(in: .whitespaces))
        } else if t.hasPrefix("[POSITIVE]") {
            return ScreenAnalysis(observation: t, badgeClass: "badge-positive", badgeLabel: "POSITIVE",
                                  observationText: String(t.dropFirst("[POSITIVE]".count)).trimmingCharacters(in: .whitespaces))
        }
        return ScreenAnalysis(observation: t, badgeClass: "badge-issue", badgeLabel: "NOTE", observationText: t)
    }

    private func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Anthropic

    private static func callAnthropic(prompt: String, images: [MobbinScreen], apiKey: String) async throws -> String {
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        for (i, s) in images.enumerated() {
            content.append(["type": "text", "text": "Screen \(i + 1)/\(images.count)"])
            content.append(["type": "image", "source": ["type": "base64", "media_type": s.mediaType, "data": s.imageBase64]])
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

    private static func callOpenAI(prompt: String, images: [MobbinScreen], apiKey: String) async throws -> String {
        var parts: [[String: Any]] = [["type": "text", "text": prompt]]
        for (i, s) in images.enumerated() {
            parts.append(["type": "text", "text": "Screen \(i + 1)/\(images.count)"])
            parts.append(["type": "image_url", "image_url": ["url": "data:\(s.mediaType);base64,\(s.imageBase64)"]])
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

    private static func callGemini(prompt: String, images: [MobbinScreen], apiKey: String) async throws -> String {
        var parts: [[String: Any]] = [["text": prompt]]
        for (i, s) in images.enumerated() {
            parts.append(["text": "Screen \(i + 1)/\(images.count)"])
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

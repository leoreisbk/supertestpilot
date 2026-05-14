import Foundation

enum MobbinRunnerError: LocalizedError {
    case claudeNotFound

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude CLI not found. Install Claude Code from claude.ai/code."
        }
    }
}

struct MobbinRunner {
    let config: RunConfig
    let settings: SettingsStore

    @MainActor
    func makeProcess(outputPath: String) throws -> Process {
        let claudeBin = resolveClaude()
        guard let claudeBin else { throw MobbinRunnerError.claudeNotFound }

        let platform = "ios"
        let langCode = config.language.rawValue
        let persona = config.personaContent ?? ""

        let (lblTitle, lblSummary, lblScreens, lblScreen) = langCode == "pt-BR"
            ? ("Relatório de Pesquisa TestPilot", "Resumo", "Telas analisadas", "Tela")
            : ("TestPilot Research Report", "Summary", "Analyzed screens", "Screen")

        let prompt = """
You are a UX research assistant. Use the mcp__mobbin__search_screens tool to search Mobbin for screens from a specific app, then analyze each screen against the objective.

APP_NAME: \(config.mobbinAppName)
DESCRIPTION: \(config.mobbinDescription.isEmpty ? "(any screens)" : config.mobbinDescription)
OBJECTIVE: \(config.objective)
PLATFORM: \(platform)
LIMIT: \(config.mobbinLimit)
OUTPUT_PATH: \(outputPath)
LANG: \(langCode)
PERSONA: \(persona)

## Instructions

1. Search for screens from APP_NAME using mcp__mobbin__search_screens. Try up to 3 queries (stop early once you have LIMIT results from that app):
   - If DESCRIPTION is provided: "\(config.mobbinAppName) \(config.mobbinDescription)"
   - "\(config.mobbinAppName) app screens"
   - "\(config.mobbinAppName) mobile interface"
   Keep only results where app_name contains "\(config.mobbinAppName)" (case-insensitive). Discard results from other apps.

2. For each screen retained, before analyzing it print exactly:
   TESTPILOT_STEP: Screen X/N — <app_name>
   (where X is the 1-based index and N is the total count)

3. Analyze each screen image against the OBJECTIVE. Write one observation per screen, prefixed with exactly one of:
   - [CRITICAL] for severe UX problems
   - [ISSUE] for moderate UX problems
   - [POSITIVE] for good UX patterns

4. After analyzing all screens, write a summary of 3-5 cross-app patterns.

5. Build a complete HTML report and write it to OUTPUT_PATH using the Write tool.

6. After writing the file, print exactly:
   TESTPILOT_REPORT_PATH=\(outputPath)

Do NOT open the file.

## HTML format

Use this CSS verbatim:
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
@media (prefers-color-scheme: dark) { body { background: #1c1c1e; color: #f5f5f7; } .header { background: #2c2c2e; border-bottom-color: #3a3a3c; } .header .objective { color: #aeaeb2; } .summary-box, .step { background: #2c2c2e; box-shadow: 0 1px 3px rgba(0,0,0,.3); } .step-header { background: #3a3a3c; } .step-num { color: #636366; } .summary-content { color: #ebebf0; } .step-obs-col { color: #ebebf0; } }
</style>

HTML structure (substitute real values):

<!DOCTYPE html>
<html lang="\(langCode)">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>\(lblTitle)</title>
<style><!-- CSS above --></style></head>
<body>
<div class="header">
  <h1>\(lblTitle)</h1>
  <div class="objective">OBJECTIVE_TEXT</div>
  <div class="meta">Query: &ldquo;QUERY_TEXT&rdquo; &middot; N screens</div>
  <!-- if PERSONA is non-empty, add a persona card:
  <div class="persona-card"><div class="persona-icon">👤</div><div><div class="persona-label">Persona</div><div class="persona-text">PERSONA_TEXT</div></div></div>
  -->
</div>
<div class="summary-box"><h2>\(lblSummary)</h2><div class="summary-content"><ul><li>Pattern 1...</li><li>Pattern 2...</li></ul></div></div>
<div class="steps"><h2>\(lblScreens)</h2>
  <!-- one .step card per screen -->
  <div class="step">
    <div class="step-header">
      <span class="step-num">\(lblScreen) 1</span>
      <span class="action"><a href="MOBBIN_URL" target="_blank">APP_NAME</a></span>
    </div>
    <div class="step-body">
      <div class="step-img-col"><img src="data:image/webp;base64,BASE64_DATA" loading="lazy"/></div>
      <div class="step-obs-col"><p><span class="badge badge-critical">CRITICAL</span> observation text</p></div>
    </div>
  </div>
</div>
</body></html>

For the badge class: [CRITICAL] → badge-critical, [ISSUE] → badge-issue, [POSITIVE] → badge-positive.
Embed screen images as base64 data URIs using the image data returned by mcp__mobbin__search_screens.
If a Mobbin URL is available for the screen, link the app name to it; otherwise just show the app name as plain text.
"""

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudeBin)
        proc.arguments = ["-p", prompt, "--output-format", "text"]
        return proc
    }

    private func resolveClaude() -> String? {
        let fromPath: String? = ProcessInfo.processInfo.environment["PATH"].flatMap { path in
            path.components(separatedBy: ":").compactMap { dir -> String? in
                let full = (dir as NSString).appendingPathComponent("claude")
                return FileManager.default.isExecutableFile(atPath: full) ? full : nil
            }.first
        }
        let candidates: [String?] = [
            fromPath,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/local/claude").path,
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        return candidates.compactMap { $0 }.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
}

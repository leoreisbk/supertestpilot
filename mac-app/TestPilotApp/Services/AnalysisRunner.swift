import Foundation
import AppKit
import Observation

enum AnalysisState: Equatable {
    case idle
    case running(statusLine: String)
    case completed(reportPath: String)
    case failed(error: String)
}

@MainActor
@Observable
final class AnalysisRunner {
    private(set) var state: AnalysisState = .idle
    private var process: Process?
    private var lastStdoutLine: String = ""

    func run(config: RunConfig, settings: SettingsStore) {
        guard case .idle = state else { return }

        if settings.apiKey.isEmpty {
            state = .failed(error: "API key not set — open Settings and enter your API key")
            return
        }

        let scriptURL: URL
        if !settings.scriptPath.isEmpty {
            let expanded = NSString(string: settings.scriptPath).expandingTildeInPath
            scriptURL = URL(fileURLWithPath: expanded)
        } else if let bundled = Bundle.main.url(forResource: "testpilot", withExtension: nil) {
            scriptURL = bundled
        } else {
            state = .failed(error: "testpilot script not found — set the script path in Settings")
            return
        }

        let outputPath = NSString(string: config.outputPath).expandingTildeInPath

        let filledParams = config.parameters.filter { !$0.key.isEmpty && !$0.value.isEmpty }
        let effectiveObjective: String
        if filledParams.isEmpty {
            effectiveObjective = config.objective
        } else {
            let lines = filledParams.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
            effectiveObjective = config.objective + "\n\nTest parameters:\n" + lines
        }

        var args: [String] = [
            "analyze",
            "--platform", config.platform.rawValue,
            "--app",      config.appName,
            "--objective", effectiveObjective,
            "--lang",     config.language.rawValue,
            "--max-steps", "\(config.maxSteps)",
            "--output",   outputPath
        ]

        if let device = config.selectedDevice, device.isPhysical {
            args += ["--device", device.id]
            if !settings.teamId.isEmpty {
                args += ["--team-id", settings.teamId]
            }
        }

        let provider = config.providerOverride ?? settings.provider
        args += ["--provider", provider.rawValue]

        var env = ProcessInfo.processInfo.environment
        // Augment PATH with Homebrew and common tool locations that are present in
        // a developer's shell but absent from the minimal launchd environment.
        let extraPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin",
                          "/usr/local/bin", "/usr/local/sbin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extraPaths.joined(separator: ":") + ":" + currentPath
        env["TESTPILOT_API_KEY"]  = settings.apiKey
        env["TESTPILOT_PROVIDER"] = provider.rawValue
        if !settings.teamId.isEmpty {
            env["TESTPILOT_TEAM_ID"] = settings.teamId
        }

        let p = Process()
        p.executableURL = scriptURL
        p.arguments = args
        p.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError  = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let line = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty
            else { return }
            DispatchQueue.main.async {
                self?.lastStdoutLine = line
                self?.state = .running(statusLine: line)
            }
        }

        p.terminationHandler = { [weak self] proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            // Drain remaining stderr synchronously after process exits
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let lastStderr = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                // Don't overwrite state if already reset by cancel()
                guard case .running = self?.state else { return }
                if proc.terminationStatus == 0 {
                    self?.state = .completed(reportPath: outputPath)
                } else {
                    let fallback = self?.lastStdoutLine ?? ""
                    let msg = !lastStderr.isEmpty ? lastStderr
                            : !fallback.isEmpty    ? fallback
                            : "Analysis failed (exit \(proc.terminationStatus))"
                    self?.state = .failed(error: msg)
                }
            }
        }

        lastStdoutLine = ""
        state = .running(statusLine: "Starting analysis…")
        process = p

        do {
            try p.run()
        } catch {
            state = .failed(error: error.localizedDescription)
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
        state = .idle
    }

    func reset() {
        state = .idle
    }
}

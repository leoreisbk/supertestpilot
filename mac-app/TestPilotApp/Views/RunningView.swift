import SwiftUI
import AppKit

struct RunningView: View {
    var runner: AnalysisRunner
    var config: RunConfig

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 4) {
                Text(config.appName)
                    .font(.title2.weight(.semibold))
                Text(config.objective)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            // State-driven content
            switch runner.state {
            case .running(let statusLine):
                NeuralOrbView(platform: config.platform)
                ZStack {
                    Text(statusLine)
                        .id(statusLine)
                        .transition(.opacity)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .animation(.easeInOut(duration: 0.4), value: statusLine)
                Button("Cancel") { runner.cancel() }
                    .buttonStyle(.bordered)

            case .testRunning(let steps):
                NeuralOrbView(platform: config.platform)
                ZStack {
                    if let current = steps.last {
                        Text(current.message)
                            .id(steps.count)
                            .transition(.opacity)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: steps.count)
                Button("Cancel") { runner.cancel() }
                    .buttonStyle(.bordered)

            case .completed(let path):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
                Text("Analysis complete")
                    .font(.title2.weight(.semibold))
                if !runner.analyzeSteps.isEmpty {
                    StepListView(steps: runner.analyzeSteps)
                        .layoutPriority(1)
                }
                HStack(spacing: 16) {
                    Button("Open Report") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Run Another") { runner.reset() }
                        .buttonStyle(.bordered)
                }

            case .testPassed(let reason, let steps):
                VerdictBannerView(passed: true, reason: reason)
                StepListView(steps: steps)
                    .layoutPriority(1)
                Button("Run Again") { runner.reset() }
                    .buttonStyle(.bordered)

            case .testFailed(let reason, let steps):
                VerdictBannerView(passed: false, reason: reason)
                StepListView(steps: steps)
                    .layoutPriority(1)
                Button("Run Again") { runner.reset() }
                    .buttonStyle(.bordered)

            case .failed(let error):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                Text(config.mode == .test ? "Test failed" : "Analysis failed")
                    .font(.title3.weight(.medium))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Try Again") { runner.reset() }
                    .buttonStyle(.bordered)

            case .idle:
                EmptyView()

            case .webLoginPending:
                NeuralOrbView(platform: config.platform)
                Text("Browser open — log in and tap Save Session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Cancel") { runner.cancel() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.4), value: runner.state)
    }
}

private struct StepListView: View {
    let steps: [TestStep]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.cached ? "arrow.triangle.2.circlepath" : "circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.top, 3)
                        Text(step.message)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct VerdictBannerView: View {
    let passed: Bool
    let reason: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(passed ? .green : .red)
                .transition(.scale.combined(with: .opacity))
            Text(passed ? "PASSED" : "FAILED")
                .font(.title2.weight(.bold))
                .foregroundStyle(passed ? .green : .red)
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
    }
}

import SwiftUI
import AppKit

struct RunningView: View {
    var runner: AnalysisRunner
    var config: RunConfig

    var body: some View {
        VStack(spacing: 28) {
            // Header
            VStack(spacing: 6) {
                Text(config.appName)
                    .font(.headline)
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
                RobotAnimationView()
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .animation(.easeInOut(duration: 0.3), value: statusLine)
                Button("Cancel") { runner.cancel() }
                    .buttonStyle(.bordered)

            case .completed(let path):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
                Text("Analysis complete")
                    .font(.title3.weight(.medium))
                HStack(spacing: 16) {
                    Button("Open Report") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Run Another") { runner.reset() }
                        .buttonStyle(.bordered)
                }

            case .failed(let error):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                Text("Analysis failed")
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
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.4), value: runner.state)
    }
}

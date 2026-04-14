import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case newRun  = "New Run"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .newRun:  return "plus.circle"
        case .history: return "clock"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .newRun
    @State private var config   = RunConfig()
    @State private var runner   = AnalysisRunner()
    @State private var settings = SettingsStore()
    @State private var history  = HistoryStore()
    @State private var detector = DeviceDetector()
    @State private var artifactManager = ArtifactManager()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 160, max: 180)
        } detail: {
            detail
                .frame(minWidth: 560, minHeight: 440)
        }
        .task { await artifactManager.ensureArtifacts() }
        .overlay(alignment: .bottom) {
            ArtifactToastView(manager: artifactManager)
                .padding(.bottom, 16)
        }
        .onChange(of: runner.state) { _, newState in
            let displayName = config.platform == .web ? config.url : config.appName
            switch newState {
            case .completed(let path):
                history.append(RunRecord(
                    appName: displayName,
                    platform: config.platform,
                    objective: config.objective,
                    reportPath: path,
                    mode: .analyze
                ))
            case .testPassed(let reason, _):
                history.append(RunRecord(
                    appName: displayName,
                    platform: config.platform,
                    objective: config.objective,
                    reportPath: "",
                    mode: .test,
                    testOutcome: TestOutcome(passed: true, reason: reason)
                ))
            case .testFailed(let reason, _):
                history.append(RunRecord(
                    appName: displayName,
                    platform: config.platform,
                    objective: config.objective,
                    reportPath: "",
                    mode: .test,
                    testOutcome: TestOutcome(passed: false, reason: reason)
                ))
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .newRun, .none:
            switch runner.state {
            case .idle:
                RunView(config: config, detector: detector,
                        settings: settings, runner: runner)
            default:
                RunningView(runner: runner, config: config)
            }
        case .history:
            HistoryView(store: history)
        case .settings:
            SettingsView(store: settings, onCheckForUpdates: {
                Task { await artifactManager.ensureArtifacts() }
            })
        }
    }
}

// MARK: - ArtifactToastView

private struct ArtifactToastView: View {
    let manager: ArtifactManager

    @State private var showReady = false
    @State private var visible   = false

    var body: some View {
        Group {
            if visible {
                toastContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(duration: 0.35), value: visible)
        .onChange(of: manager.state) { _, state in
            handleStateChange(state)
        }
        .onAppear {
            handleStateChange(manager.state)
        }
    }

    @ViewBuilder
    private var toastContent: some View {
        switch manager.state {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Checking for updates…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

        case .downloading(let artifact, let progress):
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Downloading \(artifact)…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(.blue)
            }

        case .failed(let msg):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 260, alignment: .leading)
                Button("Retry") {
                    Task { await manager.ensureArtifacts() }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }

        case .ready where showReady:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ready")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

        default:
            EmptyView()
        }
    }

    private func handleStateChange(_ state: ArtifactState) {
        switch state {
        case .checking, .downloading, .failed:
            visible = true
            showReady = false
        case .ready:
            showReady = true
            visible = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { visible = false }
                try? await Task.sleep(for: .milliseconds(400))
                showReady = false
            }
        case .unknown:
            visible = false
        }
    }
}

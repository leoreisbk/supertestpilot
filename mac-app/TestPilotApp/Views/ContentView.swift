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
        .sheet(isPresented: .constant(!artifactManager.isReady)) {
            SetupSheet(manager: artifactManager)
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

// MARK: - SetupSheet

struct SetupSheet: View {
    let manager: ArtifactManager

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Setting up TestPilot")
                .font(.title2.bold())

            stateContent
        }
        .padding(40)
        .frame(width: 400)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch manager.state {
        case .checking:
            ProgressView("Checking for updates…")
        case .downloading(let artifact, let progress):
            VStack(spacing: 12) {
                Text(artifact)
                    .font(.body)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        case .failed(let msg):
            VStack(spacing: 16) {
                Text(msg)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await manager.ensureArtifacts() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .ready:
            EmptyView()
        case .unknown:
            ProgressView()
        }
    }
}

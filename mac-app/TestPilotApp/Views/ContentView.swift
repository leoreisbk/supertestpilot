import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case newAnalysis = "New Analysis"
    case history     = "History"
    case settings    = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .newAnalysis: return "plus.circle"
        case .history:     return "clock"
        case .settings:    return "gear"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .newAnalysis
    @State private var config   = RunConfig()
    @State private var runner   = AnalysisRunner()
    @State private var settings = SettingsStore()
    @State private var history  = HistoryStore()
    @State private var detector = DeviceDetector()

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
        .onChange(of: runner.state) { _, newState in
            switch newState {
            case .completed(let path):
                history.append(RunRecord(
                    appName: config.appName,
                    platform: config.platform,
                    objective: config.objective,
                    reportPath: path,
                    mode: .analyze
                ))
            case .testPassed(let reason, _):
                history.append(RunRecord(
                    appName: config.appName,
                    platform: config.platform,
                    objective: config.objective,
                    reportPath: "",
                    mode: .test,
                    testOutcome: TestOutcome(passed: true, reason: reason)
                ))
            case .testFailed(let reason, _):
                history.append(RunRecord(
                    appName: config.appName,
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
        case .newAnalysis, .none:
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
            SettingsView(store: settings)
        }
    }
}

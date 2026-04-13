import SwiftUI
import AppKit

struct RunView: View {
    @Bindable var config: RunConfig
    var detector: DeviceDetector
    var settings: SettingsStore
    var runner: AnalysisRunner

    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("Required") {
                Picker("Mode", selection: $config.mode) {
                    ForEach(RunMode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Platform", selection: $config.platform) {
                    ForEach(Platform.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: config.platform) { _, _ in
                    config.selectedDevice = nil
                    Task { await detector.refresh(for: config.platform) }
                }

                if config.platform != .web {
                    HStack {
                        Picker("Device", selection: $config.selectedDevice) {
                            Text("Select a device").tag(Optional<DeviceInfo>(nil))
                            ForEach(detector.devices) { device in
                                Text(device.displayName).tag(Optional(device))
                            }
                        }
                        if detector.isRefreshing {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button {
                                Task { await detector.refresh(for: config.platform) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh device list")
                        }
                    }

                    TextField("App name", text: $config.appName)
                } else {
                    TextField("URL", text: $config.url)
                        .textContentType(.URL)
                }

                ZStack(alignment: .topLeading) {
                    if config.objective.isEmpty {
                        let placeholder = config.mode == .test
                            ? "Check if the Buy button is enabled on the product page…"
                            : "Describe what to analyze…"
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $config.objective)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                }

                TextField("Username (optional)", text: $config.username)
                SecureField("Password (optional)", text: $config.password)

                if config.platform == .web {
                    Button("Manage Session…") {
                        runner.webLogin(config: config, settings: settings)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .help("Open a browser to log in manually — useful for SSO or OAuth")
                    .disabled(config.url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
                Picker("Language", selection: $config.language) {
                    ForEach(Language.allCases) { l in
                        Text(l.displayName).tag(l)
                    }
                }

                Stepper("Max steps: \(config.maxSteps)",
                        value: $config.maxSteps, in: 1...60)

                if config.mode == .analyze {
                    HStack {
                        TextField("Output path", text: $config.outputPath)
                        Button("Choose…") {
                            let panel = NSSavePanel()
                            panel.allowedContentTypes = [.html]
                            panel.nameFieldStringValue = "report.html"
                            if panel.runModal() == .OK, let url = panel.url {
                                config.outputPath = (url.path as NSString).abbreviatingWithTildeInPath
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Picker("Provider", selection: $config.providerOverride) {
                    Text("From Settings (\(settings.provider.displayName))")
                        .tag(Optional<AIProvider>(nil))
                    ForEach(AIProvider.allCases) { p in
                        Text(p.displayName).tag(Optional(p))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            let label = config.mode == .test ? "Run Test" : "Run Analysis"
            Button(label) {
                runner.run(config: config, settings: settings)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding()
            .disabled(!config.isValid)
        }
        .task {
            await detector.refresh(for: config.platform)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await detector.refresh(for: config.platform) }
        }
        .navigationTitle(config.mode == .test ? "New Test" : "New Analysis")
        .sheet(isPresented: Binding(
            get: { runner.state == .webLoginPending },
            set: { _ in } // dismissal handled by Save Session / Cancel buttons only
        )) {
            VStack(spacing: 20) {
                Text("Log in to \(config.url)")
                    .font(.headline)
                Text("A browser window has opened. Complete login, then tap Save Session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Save Session") {
                    runner.saveSession()
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel") {
                    runner.cancel()
                }
                .buttonStyle(.bordered)
            }
            .padding(32)
            .frame(minWidth: 320)
        }
    }
}

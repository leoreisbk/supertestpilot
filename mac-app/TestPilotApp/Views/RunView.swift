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
            }

            Section("Parameters") {
                ForEach($config.parameters) { $param in
                    HStack(spacing: 8) {
                        TextField("Key", text: $param.key)
                            .frame(maxWidth: 120)
                        if param.isSecret {
                            SecureField("Value", text: $param.value)
                        } else {
                            TextField("Value", text: $param.value)
                        }
                        Button(role: .destructive) {
                            config.parameters.removeAll { $0.id == param.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    config.parameters.append(RunParameter())
                } label: {
                    Label("Add Parameter", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
                Picker("Language", selection: $config.language) {
                    ForEach(Language.allCases) { l in
                        Text(l.displayName).tag(l)
                    }
                }

                Stepper("Max steps: \(config.maxSteps)",
                        value: $config.maxSteps, in: 1...100)

                if config.mode == .analyze {
                    HStack {
                        TextField("Output path", text: $config.outputPath)
                        Button("Choose…") {
                            let panel = NSSavePanel()
                            panel.allowedContentTypes = [.html]
                            panel.nameFieldStringValue = "report.html"
                            if panel.runModal() == .OK, let url = panel.url {
                                config.outputPath = url.path
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
    }
}

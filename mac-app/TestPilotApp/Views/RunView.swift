import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RunView: View {
    @Bindable var config: RunConfig
    var detector: DeviceDetector
    var settings: SettingsStore
    var runner: AnalysisRunner

    @State private var showAdvanced = false

    private var runButtonLabel: String {
        switch config.mode {
        case .test:     return "Run Test"
        case .research: return "Run Research"
        case .analyze:  return "Run Analysis"
        }
    }

    var body: some View {
        Form {
            Section("Required") {
                modePicker
                platformOrSourceSection
                targetSection
                objectiveSection
                credentialsSection
                personaSection
            }
            advancedSection
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Button(runButtonLabel) {
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
        .navigationTitle(config.mode == .test ? "New Test" : config.mode == .research ? "New Research" : "New Analysis")
        .sheet(isPresented: Binding(
            get: { runner.state == .webLoginPending },
            set: { _ in }
        )) {
            VStack(spacing: 20) {
                Text("Log in to \(config.mode == .research ? "mobbin.com" : config.url)")
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

    @ViewBuilder
    private var modePicker: some View {
        Picker("Mode", selection: $config.mode) {
            ForEach(RunMode.allCases) { m in
                Text(m.displayName).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var platformOrSourceSection: some View {
        if config.mode != .research {
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
        }
        if config.mode == .research {
            Picker("Source", selection: $config.mobbinSource) {
                ForEach(MobbinSource.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            if config.mobbinSource == .flowUrl {
                TextField("Mobbin Flow URL", text: $config.mobbinFlowUrl)
                    .textContentType(.URL)
            } else {
                TextField("App name", text: $config.mobbinAppName)
                TextField("Flow name", text: $config.mobbinFlowName)
            }
            let mobbinSessionExists = FileManager.default.fileExists(
                atPath: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".testpilot/sessions/mobbin.com.json").path
            )
            if mobbinSessionExists {
                HStack(spacing: 8) {
                    Label("Connected to Mobbin", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Button("Reconnect") {
                        runner.mobbinLogin(config: config, settings: settings)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .help("Re-authenticate with Mobbin if your session has expired")
                }
            } else {
                Button("Connect Mobbin…") {
                    runner.mobbinLogin(config: config, settings: settings)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
                .help("Open a browser to log in to Mobbin — required before running research")
            }
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        if config.mode != .research {
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
                TextField("Bundle ID (optional override)", text: $config.bundleId)
                    .foregroundStyle(config.bundleId.isEmpty ? .primary : .secondary)
                    .help("If the app can't be found by name, enter its bundle ID directly (e.g. com.pgatour.PGATOUR)")
            } else {
                TextField("URL", text: $config.url)
                    .textContentType(.URL)
            }
        }
    }

    @ViewBuilder
    private var objectiveSection: some View {
        let placeholder = config.mode == .test
            ? "Check if the Buy button is enabled on the product page…"
            : config.personaPath.isEmpty
                ? "Describe what to analyze…"
                : "Optional — persona defines the focus. Add a specific goal to narrow it down."
        MultilineTextField(text: $config.objective, placeholder: placeholder)
            .frame(minHeight: 80)
    }

    @ViewBuilder
    private var credentialsSection: some View {
        TextField("Username (optional)", text: $config.username)
        SecureField("Password (optional)", text: $config.password)
        if config.platform == .web && config.mode != .research {
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

    @ViewBuilder
    private var personaSection: some View {
        if config.mode == .analyze {
            HStack {
                if config.personaPath.isEmpty {
                    Text("No persona")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(URL(fileURLWithPath: config.personaPath).lastPathComponent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    Button {
                        config.personaPath = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove persona")
                }
                Button("Persona…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .text]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.title = "Choose Persona File"
                    if panel.runModal() == .OK, let url = panel.url {
                        config.personaPath = url.path
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
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
}

// MARK: - MultilineTextField

private struct MultilineTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlaceholderTextView()
        textView.placeholderString = placeholder
        textView.isEditable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        if textView.string != text { textView.string = text }
        textView.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineTextField
        init(_ parent: MultilineTextField) { self.parent = parent }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

private final class PlaceholderTextView: NSTextView {
    var placeholderString: String = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let x = (textContainer?.lineFragmentPadding ?? 0) + textContainerInset.width
        let y = textContainerInset.height
        NSAttributedString(string: placeholderString, attributes: [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize)
        ]).draw(at: NSPoint(x: x, y: y))
    }
}

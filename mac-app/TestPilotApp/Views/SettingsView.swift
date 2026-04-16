import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore
    @State private var apiKeyText  = ""
    @State private var rawEnvText  = ""
    @State private var showRawEnv  = false
    var onCheckForUpdates: (() -> Void)? = nil

    var body: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: $store.provider) {
                    ForEach(AIProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .onChange(of: store.provider) { _, _ in store.save() }

                SecureField("API Key", text: $apiKeyText)
                    .onAppear { apiKeyText = store.apiKey }
                    .onChange(of: apiKeyText) { _, v in
                        store.apiKey = v
                        rawEnvText = store.rawEnv
                        store.save()
                    }

                TextField("Apple Team ID (physical iOS devices)", text: $store.teamId)
                    .onChange(of: store.teamId) { _, _ in
                        rawEnvText = store.rawEnv
                        store.save()
                    }

                HStack {
                    Text("Reports folder")
                    Spacer()
                    Text(store.reportFolder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200, alignment: .trailing)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.canCreateDirectories = true
                        panel.title = "Choose Reports Folder"
                        if panel.runModal() == .OK, let url = panel.url {
                            store.reportFolder = (url.path as NSString).abbreviatingWithTildeInPath
                            store.save()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section {
                Button("Check for Updates") {
                    onCheckForUpdates?()
                }
            } footer: {
                Text("Downloads the latest TestPilot components to ~/.testpilot/.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                DisclosureGroup(".env file  (~/.testpilot/.env)", isExpanded: $showRawEnv) {
                    TextEditor(text: $rawEnvText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                        .onChange(of: rawEnvText) { _, v in
                            store.rawEnv = v
                            store.save()
                            apiKeyText = store.apiKey   // sync back
                        }
                }
            } footer: {
                Text("Edits here sync with the fields above and are written to disk for use with the CLI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { rawEnvText = store.rawEnv }
        .navigationTitle("Settings")
    }
}

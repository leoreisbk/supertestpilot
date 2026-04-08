import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore
    @State private var apiKeyText  = ""
    @State private var rawEnvText  = ""
    @State private var showRawEnv  = false

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

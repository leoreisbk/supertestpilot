import SwiftUI
import AppKit

struct HistoryView: View {
    var store: HistoryStore

    var body: some View {
        Group {
            if store.records.isEmpty {
                ContentUnavailableView(
                    "No analyses yet",
                    systemImage: "clock",
                    description: Text("Run an analysis to see it here.")
                )
            } else {
                List(store.records) { record in
                    HistoryRowView(record: record)
                }
            }
        }
        .navigationTitle("History")
    }
}

private struct HistoryRowView: View {
    let record: RunRecord
    @State private var reportMissing = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.appName).fontWeight(.medium)
                    Text(record.platform.rawValue.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(record.platform == .ios
                                    ? Color.blue.opacity(0.15)
                                    : Color.green.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(record.objective)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(record.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Button("Open Report") {
                    let path = record.reportPath
                    if FileManager.default.fileExists(atPath: path) {
                        reportMissing = false
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    } else {
                        reportMissing = true
                    }
                }
                .buttonStyle(.bordered)
                if reportMissing {
                    Text("File not found")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

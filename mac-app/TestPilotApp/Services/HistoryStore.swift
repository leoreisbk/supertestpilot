import Foundation
import Observation

@Observable
final class HistoryStore {
    private(set) var records: [RunRecord] = []
    private let maxEntries: Int
    private let fileURL: URL

    init(
        fileURL: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TestPilot/history.json"),
        maxEntries: Int = 50
    ) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
        load()
    }

    func append(_ record: RunRecord) {
        records.insert(record, at: 0)
        if records.count > maxEntries {
            records = Array(records.prefix(maxEntries))
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([RunRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(records) else { return }
        // Intentional: silent failure — history loss on disk error is acceptable for this MVP
        try? data.write(to: fileURL, options: .atomic)
    }
}

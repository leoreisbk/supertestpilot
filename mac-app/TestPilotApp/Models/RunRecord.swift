import Foundation

struct TestOutcome: Codable, Equatable {
    let passed: Bool
    let reason: String
}

struct RunRecord: Codable, Identifiable {
    let id: UUID
    let appName: String
    let platform: Platform
    let objective: String
    let reportPath: String
    let mode: RunMode
    let testOutcome: TestOutcome?
    let date: Date

    init(
        appName: String,
        platform: Platform,
        objective: String,
        reportPath: String,
        mode: RunMode = .analyze,
        testOutcome: TestOutcome? = nil
    ) {
        self.id = UUID()
        self.appName = appName
        self.platform = platform
        self.objective = objective
        self.reportPath = reportPath
        self.mode = mode
        self.testOutcome = testOutcome
        self.date = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        appName = try c.decode(String.self, forKey: .appName)
        platform = try c.decode(Platform.self, forKey: .platform)
        objective = try c.decode(String.self, forKey: .objective)
        reportPath = try c.decode(String.self, forKey: .reportPath)
        mode = try c.decodeIfPresent(RunMode.self, forKey: .mode) ?? .analyze
        testOutcome = try c.decodeIfPresent(TestOutcome.self, forKey: .testOutcome)
        date = try c.decode(Date.self, forKey: .date)
    }
}

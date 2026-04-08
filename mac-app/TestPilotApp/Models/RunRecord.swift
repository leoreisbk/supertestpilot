import Foundation

struct RunRecord: Codable, Identifiable {
    let id: UUID
    let appName: String
    let platform: Platform
    let objective: String
    let reportPath: String
    let date: Date

    init(appName: String, platform: Platform, objective: String, reportPath: String) {
        self.id = UUID()
        self.appName = appName
        self.platform = platform
        self.objective = objective
        self.reportPath = reportPath
        self.date = Date()
    }
}

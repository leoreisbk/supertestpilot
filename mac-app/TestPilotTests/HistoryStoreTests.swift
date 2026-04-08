import XCTest
@testable import TestPilotApp

final class HistoryStoreTests: XCTestCase {
    var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testAppendAddsRecord() {
        let store = HistoryStore(fileURL: tempURL)
        let record = RunRecord(appName: "Pharmia", platform: .ios,
                               objective: "Check flow", reportPath: "/tmp/r.html")
        store.append(record)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records[0].appName, "Pharmia")
    }

    func testNewestRecordIsFirst() {
        let store = HistoryStore(fileURL: tempURL)
        store.append(RunRecord(appName: "First", platform: .ios, objective: "o", reportPath: "/r"))
        store.append(RunRecord(appName: "Second", platform: .ios, objective: "o", reportPath: "/r"))
        XCTAssertEqual(store.records[0].appName, "Second")
    }

    func testMaxEntriesEnforced() {
        let store = HistoryStore(fileURL: tempURL, maxEntries: 3)
        for i in 0..<5 {
            store.append(RunRecord(appName: "App\(i)", platform: .ios,
                                   objective: "o", reportPath: "/r"))
        }
        XCTAssertEqual(store.records.count, 3)
    }

    func testPersistsAcrossInstances() {
        let store1 = HistoryStore(fileURL: tempURL)
        store1.append(RunRecord(appName: "Saved", platform: .ios,
                                objective: "o", reportPath: "/r"))

        let store2 = HistoryStore(fileURL: tempURL)
        XCTAssertEqual(store2.records.count, 1)
        XCTAssertEqual(store2.records[0].appName, "Saved")
    }
}

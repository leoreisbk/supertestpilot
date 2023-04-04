import Foundation
import Logging

struct Device: Decodable {
    let udid: String
    let name: String
    let osVersion: String
    let isSimulator: Bool
    
    init(
        udid: String,
        name: String,
        osVersion: String = "",
        isSimulator: Bool = false
    ) {
        self.udid = udid
        self.name = name
        self.osVersion = osVersion
        self.isSimulator = isSimulator
    }
}

struct TestDestination {
    static func getDevices() throws -> [Device] {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcrun")
        process.standardOutput = output
        process.arguments = ["xctrace", "list", "devices"]
        
        try ProcessPool.shared.run(process: process)
        process.waitUntilExit()
        
        guard let data = try output.fileHandleForReading.readToEnd() else {
            return []
        }
        
        return try extractDevices(from: String(data: data, encoding: .utf8) ?? "")
    }
    
    static func extractDevices(from input: String) throws -> [Device] {
        let lines = input.components(separatedBy: .newlines)
        let nameRegex = try NSRegularExpression(pattern: "^[^(]+")
        let osVersionRegex = try NSRegularExpression(pattern: "\\((\\d+\\.\\d+)\\)")
        let udidRegex = try NSRegularExpression(pattern: "\\(([A-F\\d\\-]+)\\)")

        var devices: [Device] = []
        var isSimulator = false
        lines.forEach { line in
            if line.contains("Simulators") {
                isSimulator = true
            }
            
            guard line.contains("iPhone") || line.contains("iPad") else {
                return
            }
            
            let nameNSRange = nameRegex.rangeOfFirstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))
            let osNSRange = osVersionRegex.rangeOfFirstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))
            let udidNSRange = udidRegex.rangeOfFirstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))
            
            guard let nameRange = Range(nameNSRange, in: line) else {
                return
            }
            
            let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
            let udid: String
            if let udidRange = Range(udidNSRange, in: line) {
                udid = String(line[udidRange]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            } else {
                udid = ""
            }
            
            let os: String
            if let osVersionRange = Range(osNSRange, in: line) {
                os = String(line[osVersionRange]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            } else {
                os = ""
            }
            
            devices.append(Device(udid: udid, name: name, osVersion: os, isSimulator: isSimulator))
        }
            
        return devices
    }
}

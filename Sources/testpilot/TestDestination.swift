import Foundation
import Logging
import ArgumentParser
import Version

private let logger = Logger(label: #file.lastPathComponent)

struct Device: Decodable {
    let udid: String
    let name: String
    let osVersion: String
    let isSimulator: Bool

    var version: Version {
        Version(tolerant: osVersion) ?? .null
    }
    
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

class TestDestination {
    static func getDevice(withID id: String) throws -> Device {
        let devices = try getDevices()
        guard let result = devices.first(where: { $0.udid == id }) else {
            throw ValidationError("Device with UDID \(id) not found")
        }

        return result
    }

    static func promptUserForDevice() throws -> Device {
        logger.info("Finding devices to use...\n")
        let devices = try TestDestination.getDevices()
            // Ensures we're not suggesting any devices below the runner's deployment target
            .filter { $0.version >= TestProjectGenerator.runnerDeploymentVersion }

        devices
            .enumerated()
            .forEach { logger.info("\($0.offset): \($0.element.name) (\($0.element.osVersion)) \($0.element.udid)") }

        let selectedDestinationIndex = promptUserForIndex(in: devices.indices)
        return devices[selectedDestinationIndex]
    }

    private static func getDevices() throws -> [Device] {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcrun")
        process.standardOutput = output
        process.arguments = ["xctrace", "list", "devices"]

        logger.debug("Getting device list")
        try ProcessPool.shared.run(process: process)
        process.waitUntilExit()
        
        guard let data = try output.fileHandleForReading.readToEnd() else {
            return []
        }
        
        return try extractDevices(from: String(data: data, encoding: .utf8) ?? "")
    }
    
    private static func extractDevices(from input: String) throws -> [Device] {
        let lines = input.components(separatedBy: .newlines)
        let nameRegex = try NSRegularExpression(pattern: "^[^(]+")
        let osVersionRegex = try NSRegularExpression(pattern: "\\((\\d+(\\.\\d)+)\\)")
        let udidRegex = try NSRegularExpression(pattern: "\\(([A-F\\d\\-]+)\\)")

        logger.debug("Devices found:")
        logger.debug(.init(stringLiteral: input))

        var devices: [Device] = []
        var isSimulator = false
        lines.forEach { line in
            if line.contains("Simulators") {
                isSimulator = true
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

    private static func promptUserForIndex(in bounds: Range<Int>) -> Int {
        // There's no way to print using logger.info without ending in a new line
        print("\nEnter the device number (ex. 4): ", terminator: "")

        repeat {
            if
                let readLineValue = readLine(), // prompting user input
                let index = Int(readLineValue), // convert to int
                bounds.contains(index) // check if index within bounds
            {
                return index
            }

            print("Invalid device selected. Please select a number between 0 and \(bounds.upperBound - 1) (ex. 0): ", terminator: "")
        } while true
    }
}

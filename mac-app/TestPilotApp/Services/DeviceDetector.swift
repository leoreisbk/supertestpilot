import Foundation
import Observation

@MainActor
@Observable
final class DeviceDetector {
    private(set) var devices: [DeviceInfo] = []
    private(set) var isRefreshing = false

    func refresh(for platform: Platform) async {
        isRefreshing = true
        let found: [DeviceInfo]
        switch platform {
        case .ios:     found = await fetchIOSDevices()
        case .android: found = await fetchAndroidDevices()
        }
        devices = found
        isRefreshing = false
    }

    // MARK: - iOS

    private func fetchIOSDevices() async -> [DeviceInfo] {
        async let simulators = fetchBootedSimulators()
        async let physical   = fetchPhysicalDevices()
        return await simulators + physical
    }

    private func fetchBootedSimulators() async -> [DeviceInfo] {
        guard let output = await shell("/usr/bin/xcrun",
                                       args: ["simctl", "list", "devices", "--json"]),
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesMap = json["devices"] as? [String: [[String: Any]]]
        else { return [] }

        return devicesMap.values.flatMap { list in
            list.compactMap { d -> DeviceInfo? in
                guard let state = d["state"] as? String, state == "Booted",
                      let udid = d["udid"] as? String,
                      let name = d["name"] as? String
                else { return nil }
                return DeviceInfo(id: udid, name: name, type: .simulator)
            }
        }
    }

    private func fetchPhysicalDevices() async -> [DeviceInfo] {
        // devicectl outputs JSON to a temp file
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        guard (await shell("/usr/bin/xcrun",
                           args: ["devicectl", "list", "devices",
                                  "--json-output", tmp.path])) != nil,
              let data = try? Data(contentsOf: tmp),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let list = result["devices"] as? [[String: Any]]
        else { return [] }

        return list.compactMap { d -> DeviceInfo? in
            guard let udid = d["identifier"] as? String,
                  let props = d["deviceProperties"] as? [String: Any],
                  let name = props["name"] as? String
            else { return nil }
            return DeviceInfo(id: udid, name: name, type: .physical)
        }
    }

    // MARK: - Android

    private func fetchAndroidDevices() async -> [DeviceInfo] {
        guard let output = await shell("/usr/bin/env", args: ["adb", "devices"]) else { return [] }
        return output
            .split(separator: "\n")
            .dropFirst() // skip "List of devices attached"
            .compactMap { line -> DeviceInfo? in
                let parts = line.split(separator: "\t")
                guard parts.count == 2 else { return nil }
                let serial = String(parts[0])
                let status = String(parts[1]).trimmingCharacters(in: .whitespaces)
                guard status == "device" else { return nil }
                let type: DeviceType = serial.hasPrefix("emulator-") ? .androidEmulator : .androidDevice
                return DeviceInfo(id: serial, name: serial, type: type)
            }
    }

    // MARK: - Shell helper

    private nonisolated func shell(_ executable: String, args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: executable)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do {
                    try p.run()
                    p.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// mac-app/TestPilotApp/Services/ArtifactManager.swift
import Foundation
import Observation
import CryptoKit

private let manifestURLString = "https://github.com/leoreisbk/supertestpilot/releases/latest/download/artifacts-manifest.json"
private let artifactDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".testpilot")

// MARK: - Types

struct ArtifactManifest: Decodable {
    struct Entry: Decodable {
        let sha256: String
        let url: String
    }
    let version: String
    let artifacts: [String: Entry]
}

enum ArtifactState: Equatable {
    case unknown
    case checking
    case downloading(artifact: String, progress: Double)
    case ready
    case failed(String)
}

enum ArtifactError: LocalizedError {
    case sha256Mismatch(expected: String, actual: String)
    case unpackFailed(Int32)
    case noArtifactsOffline

    var errorDescription: String? {
        switch self {
        case .sha256Mismatch(let e, let a):
            return "Integrity check failed — expected \(e), got \(a)"
        case .unpackFailed(let code):
            return "Failed to unpack artifact (exit \(code))"
        case .noArtifactsOffline:
            return "Could not reach GitHub to download components. Connect to the internet and relaunch."
        }
    }
}

// MARK: - ArtifactManager

@MainActor
@Observable
final class ArtifactManager {
    private(set) var state: ArtifactState = .unknown

    var isReady: Bool { state == .ready }

    func ensureArtifacts() async {
        #if DEBUG
        state = .ready
        return
        #endif

        state = .checking

        guard let manifestURL = URL(string: manifestURLString) else { return }

        let manifest: ArtifactManifest
        let manifestData: Data
        do {
            (manifestData, _) = try await URLSession.shared.data(from: manifestURL)
            manifest = try JSONDecoder().decode(ArtifactManifest.self, from: manifestData)
        } catch {
            // Offline: proceed if artifacts already exist locally
            if artifactsExistLocally() {
                state = .ready
            } else {
                state = .failed(ArtifactError.noArtifactsOffline.localizedDescription)
            }
            return
        }

        // Persist manifest for staleness checks
        let localManifestPath = artifactDir.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)
        try? manifestData.write(to: localManifestPath)

        // Download each artifact that is missing or outdated
        for (key, entry) in manifest.artifacts.sorted(by: { $0.key < $1.key }) {
            guard needsDownload(key: key, expectedSHA256: entry.sha256) else { continue }
            guard let url = URL(string: entry.url) else { continue }
            state = .downloading(artifact: key, progress: 0)
            do {
                try await download(key: key, from: url, expectedSHA256: entry.sha256)
            } catch {
                state = .failed("Failed to download \(key): \(error.localizedDescription)")
                return
            }
        }

        state = .ready
    }

    // MARK: - Private

    private func artifactsExistLocally() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: artifactDir
            .appendingPathComponent("ios/TestPilotShared.xcframework").path) &&
               fm.fileExists(atPath: artifactDir
            .appendingPathComponent("web/testpilot-web.jar").path)
    }

    private func needsDownload(key: String, expectedSHA256: String) -> Bool {
        let markerPath = artifactDir.appendingPathComponent("\(key)/.sha256")
        guard let saved = try? String(contentsOf: markerPath, encoding: .utf8),
              saved.trimmingCharacters(in: .whitespacesAndNewlines) == expectedSHA256
        else { return true }
        return false
    }

    private func download(key: String, from url: URL, expectedSHA256: String) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("testpilot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempFile = tempDir.appendingPathComponent(url.lastPathComponent)

        // Download (URLSession gives us a temp file)
        let (downloadedURL, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: downloadedURL, to: tempFile)

        // Verify SHA256
        let fileData = try Data(contentsOf: tempFile) // Note: loads full file into memory; acceptable for current artifact sizes (~40MB)
        let hash = SHA256.hash(data: fileData)
            .map { String(format: "%02x", $0) }.joined()
        guard hash == expectedSHA256 else {
            throw ArtifactError.sha256Mismatch(expected: expectedSHA256, actual: hash)
        }

        // ios artifact contains ios/ and harness/ subdirs — unpack to cache root
        let unpackDest = key == "ios" ? artifactDir : artifactDir.appendingPathComponent(key)
        let destDir = artifactDir.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: destDir)
        try FileManager.default.createDirectory(at: unpackDest, withIntermediateDirectories: true)

        let filename = url.lastPathComponent
        if filename.hasSuffix(".zip") {
            try await runCommand("/usr/bin/unzip", args: ["-q", tempFile.path, "-d", unpackDest.path])
        } else if filename.hasSuffix(".tar.gz") {
            try await runCommand("/usr/bin/tar", args: ["-xzf", tempFile.path, "-C", unpackDest.path])
        }

        // Write SHA256 marker so future launches skip this artifact
        let markerPath = destDir.appendingPathComponent(".sha256")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try expectedSHA256.write(to: markerPath, atomically: true, encoding: .utf8)
    }

    private nonisolated func runCommand(_ executable: String, args: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = args
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError  = FileHandle.nullDevice
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw ArtifactError.unpackFailed(proc.terminationStatus)
            }
        }.value
    }
}

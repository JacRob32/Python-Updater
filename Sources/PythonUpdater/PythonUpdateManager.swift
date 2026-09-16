import AppKit
import CryptoKit
import Foundation
import ServiceManagement

@MainActor
final class PythonUpdateManager {
    static let shared = PythonUpdateManager()

    private let scheduler = NSBackgroundActivityScheduler(identifier: "com.example.PythonUpdater.check")
    private let defaultPythonPath = "/usr/local/bin/python3"

    private init() {}

    func start() {
        registerForLoginItem()

        scheduler.interval = 24 * 60 * 60
        scheduler.tolerance = 60 * 60
        scheduler.repeats = true
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                defer { completion(.finished) }
                await self?.checkForUpdate()
            }
        }
    }

    func checkForUpdatesNow() async {
        await checkForUpdate()
    }

    private func registerForLoginItem() {
        do {
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Python updater could not register as a login item: %@", error.localizedDescription)
        }
    }

    private func checkForUpdate() async {
        do {
            let installedVersion = try installedPythonVersion()
            let release = try await latestRelease()

            guard installedVersion < release.version else { return }
            guard askToInstall(version: release.version) else { return }

            let installer = try await macOSInstaller(for: release)
            let packageURL = try await download(installer: installer, version: release.version)
            NSWorkspace.shared.open(packageURL)
        } catch {
            NSLog("Python update check failed: %@", error.localizedDescription)
        }
    }

    private func installedPythonVersion() throws -> SemanticVersion {
        let configuredPath = UserDefaults.standard.string(forKey: "PythonExecutablePath")
        let executablePath = configuredPath?.isEmpty == false ? configuredPath! : defaultPythonPath
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let outputString = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
              let version = SemanticVersion(pythonVersionOutput: outputString) else {
            throw UpdateError.unreadableInstalledVersion(executablePath)
        }

        return version
    }

    private func latestRelease() async throws -> ResolvedRelease {
        let url = URL(string: "https://www.python.org/api/v2/downloads/release/")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response)

        let releases = try JSONDecoder().decode([PythonRelease].self, from: data)
        guard let release = releases
            .filter({ $0.isLatest && !$0.preRelease && $0.name.hasPrefix("Python 3.") })
            .compactMap({ release in
                SemanticVersion(pythonVersionOutput: release.name).map {
                    ResolvedRelease(id: release.id, version: $0)
                }
            })
            .max(by: { $0.version < $1.version }) else {
            throw UpdateError.noStableRelease
        }

        return release
    }

    private func macOSInstaller(for release: ResolvedRelease) async throws -> PythonReleaseFile {
        let url = URL(string: "https://www.python.org/api/v2/downloads/release_file/?release=\(release.id)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response)

        let files = try JSONDecoder().decode([PythonReleaseFile].self, from: data)
        guard let installer = files.first(where: {
            $0.url.pathExtension == "pkg" && $0.name.localizedCaseInsensitiveContains("macOS 64-bit universal2 installer")
        }) else {
            throw UpdateError.noMacOSInstaller(release.version.description)
        }

        return installer
    }

    private func askToInstall(version: SemanticVersion) -> Bool {
        NSRunningApplication.current.activate(options: [.activateAllWindows])

        let alert = NSAlert()
        alert.messageText = "Python update available"
        alert.informativeText = "A new version of Python \(version) is available. Would you like to download and install it now?"
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func download(installer: PythonReleaseFile, version: SemanticVersion) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("python-\(version).pkg")
        try? FileManager.default.removeItem(at: destination)

        let (temporaryURL, response) = try await URLSession.shared.download(from: installer.url)
        try validate(response: response)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        let actualChecksum = try sha256(of: destination)
        guard actualChecksum.caseInsensitiveCompare(installer.sha256) == .orderedSame else {
            try? FileManager.default.removeItem(at: destination)
            throw UpdateError.checksumMismatch
        }

        return destination
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw UpdateError.invalidServerResponse
        }
    }

    private func sha256(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct PythonRelease: Decodable {
    let resourceURI: URL
    let name: String
    let isLatest: Bool
    let preRelease: Bool

    enum CodingKeys: String, CodingKey {
        case resourceURI = "resource_uri"
        case name
        case isLatest = "is_latest"
        case preRelease = "pre_release"
    }

    var id: String {
        resourceURI.lastPathComponent
    }
}

private struct ResolvedRelease {
    let id: String
    let version: SemanticVersion
}

private struct PythonReleaseFile: Decodable {
    let name: String
    let url: URL
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case name, url
        case sha256 = "sha256_sum"
    }
}

private struct SemanticVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(pythonVersionOutput: String) {
        let pattern = #"(?:Python\s+)?(\d+)\.(\d+)\.(\d+)"#
        guard let match = pythonVersionOutput.range(of: pattern, options: .regularExpression) else { return nil }
        let numbers = pythonVersionOutput[match]
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}

private enum UpdateError: LocalizedError {
    case unreadableInstalledVersion(String)
    case noStableRelease
    case noMacOSInstaller(String)
    case invalidServerResponse
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .unreadableInstalledVersion(let path): "Could not read Python at \(path)."
        case .noStableRelease: "No stable Python 3 release was returned by python.org."
        case .noMacOSInstaller(let version): "No universal macOS installer was found for Python \(version)."
        case .invalidServerResponse: "python.org returned an unexpected response."
        case .checksumMismatch: "The downloaded Python installer did not match its published SHA-256 checksum."
        }
    }
}
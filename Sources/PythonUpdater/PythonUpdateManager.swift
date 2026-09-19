import AppKit
import Combine
import CryptoKit
import Foundation
import ServiceManagement

@MainActor
final class PythonUpdateManager: ObservableObject {
    static let shared = PythonUpdateManager()

    private let scheduler = NSBackgroundActivityScheduler(identifier: "com.example.PythonUpdater.check")
    private let defaultPythonPath = "/usr/local/bin/python3"
    private var availableRelease: ResolvedRelease?
    private var availableInstaller: PythonReleaseFile?

    @Published private(set) var installedVersionText = "Not checked"
    @Published private(set) var availableVersionText = ""
    @Published private(set) var statusText = "Check for updates to see your current status."
    @Published private(set) var activityText = "Checking for updates..."
    @Published private(set) var lastChecked: Date?
    @Published private(set) var updateAvailable = false
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loginItemStatusText = "Not registered"

    var pythonPath: String {
        let configuredPath = UserDefaults.standard.string(forKey: "PythonExecutablePath")
        return configuredPath?.isEmpty == false ? configuredPath! : defaultPythonPath
    }

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

    func installAvailableUpdate() async {
        guard let release = availableRelease, let installer = availableInstaller, !isInstalling else { return }

        isInstalling = true
        activityText = "Downloading Python \(release.version)..."
        errorMessage = nil

        do {
            let packageURL = try await download(installer: installer, version: release.version)
            activityText = "Opening Installer..."
            NSWorkspace.shared.open(packageURL)
            statusText = "Installer opened for Python \(release.version)."
        } catch {
            errorMessage = error.localizedDescription
            statusText = "The update could not be downloaded."
        }

        isInstalling = false
    }

    func openReleasePage() {
        guard let release = availableRelease else { return }
        NSWorkspace.shared.open(release.releasePageURL)
    }

    private func registerForLoginItem() {
        do {
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
            }
            loginItemStatusText = SMAppService.mainApp.status == .enabled ? "Enabled" : "Requires approval"
        } catch {
            loginItemStatusText = "Unavailable"
            NSLog("Python updater could not register as a login item: %@", error.localizedDescription)
        }
    }

    private func checkForUpdate() async {
        guard !isChecking, !isInstalling else { return }

        isChecking = true
        activityText = "Checking python.org for releases..."
        errorMessage = nil
        defer {
            isChecking = false
            lastChecked = .now
        }

        do {
            let installedVersion = try installedPythonVersion()
            installedVersionText = installedVersion.description
            let release = try await latestRelease()

            guard installedVersion < release.version else {
                updateAvailable = false
                availableRelease = nil
                availableInstaller = nil
                statusText = "Python \(installedVersion) is up to date."
                return
            }

            let installer = try await macOSInstaller(for: release)
            availableRelease = release
            availableInstaller = installer
            availableVersionText = release.version.description
            updateAvailable = true
            statusText = "An update is available."
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Unable to check for updates."
            NSLog("Python update check failed: %@", error.localizedDescription)
        }
    }

    private func installedPythonVersion() throws -> SemanticVersion {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let outputString = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
              let version = SemanticVersion(pythonVersionOutput: outputString) else {
                        throw UpdateError.unreadableInstalledVersion(pythonPath)
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
            $0.url.scheme == "https" &&
            $0.url.host == "www.python.org" &&
            $0.url.pathExtension.lowercased() == "pkg"
        }) else {
            throw UpdateError.noMacOSInstaller(release.version.description)
        }

        return installer
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

    var releasePageURL: URL {
        let compactVersion = version.description.replacingOccurrences(of: ".", with: "")
        return URL(string: "https://www.python.org/downloads/release/python-\(compactVersion)/")!
    }
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
        case .noMacOSInstaller(let version): "No official macOS installer was found for Python \(version)."
        case .invalidServerResponse: "python.org returned an unexpected response."
        case .checksumMismatch: "The downloaded Python installer did not match its published SHA-256 checksum."
        }
    }
}
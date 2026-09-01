import Foundation

public enum BrewClientError: Error, LocalizedError {
    case brewNotFound(searched: [String])
    case commandFailed(command: String, status: Int32, stderr: String)
    case decodingFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case let .brewNotFound(searched):
            return "Homebrew was not found (looked in \(searched.joined(separator: ", "))). Install it from https://brew.sh."
        case let .commandFailed(command, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` failed (exit \(status))" + (detail.isEmpty ? "." : ": \(detail)")
        case let .decodingFailed(underlying):
            return "Could not read Homebrew's response: \(underlying.localizedDescription)"
        }
    }
}

/// A mutating brew operation Firkin can run. Queries have their own methods;
/// actions all flow through `stream(_:)` so the UI can show live output.
public enum BrewAction: Hashable, Sendable {
    case update
    case upgradeAll
    case upgrade(BrewPackage)
    case uninstall(BrewPackage)
    case pin(BrewPackage)
    case unpin(BrewPackage)
}

public actor BrewClient {
    public static let defaultSearchPaths = [
        "/opt/homebrew/bin/brew", // Apple Silicon
        "/usr/local/bin/brew",    // Intel
    ]

    public let brewURL: URL

    public init(brewPath: String? = nil) throws {
        let candidates = brewPath.map { [$0] } ?? Self.defaultSearchPaths
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw BrewClientError.brewNotFound(searched: candidates)
        }
        self.brewURL = URL(fileURLWithPath: found)
    }

    // MARK: Queries

    public func version() async throws -> String {
        let output = try await runChecked(["--version"])
        return output.standardOutput
            .components(separatedBy: .newlines)
            .first ?? "Homebrew"
    }

    /// Everything currently installed, formulae and casks, sorted by name.
    public func installedPackages() async throws -> [BrewPackage] {
        let output = try await runChecked(["info", "--json=v2", "--installed"])
        let response: BrewInfoResponse
        do {
            response = try BrewInfoResponse.decode(from: Data(output.standardOutput.utf8))
        } catch {
            throw BrewClientError.decodingFailed(underlying: error)
        }
        let formulae = response.formulae
            .filter { !($0.installed?.isEmpty ?? true) }
            .map(BrewPackage.init)
        let casks = response.casks
            .filter { $0.installed != nil }
            .map(BrewPackage.init)
        return (formulae + casks).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    // MARK: Actions

    public nonisolated func arguments(for action: BrewAction) -> [String] {
        switch action {
        case .update:
            return ["update"]
        case .upgradeAll:
            return ["upgrade"]
        case let .upgrade(package):
            return ["upgrade", package.kind == .cask ? "--cask" : "--formula", package.name]
        case let .uninstall(package):
            return ["uninstall", package.kind == .cask ? "--cask" : "--formula", package.name]
        case let .pin(package):
            return ["pin", package.name]
        case let .unpin(package):
            return ["unpin", package.name]
        }
    }

    /// Runs a mutating action, yielding combined output chunks as they arrive.
    public nonisolated func stream(_ action: BrewAction) -> AsyncThrowingStream<String, Error> {
        ProcessRunner.stream(brewURL, arguments: arguments(for: action), environment: environment)
    }

    // MARK: Plumbing

    private func runChecked(_ arguments: [String]) async throws -> ProcessOutput {
        let output = try await ProcessRunner.run(brewURL, arguments: arguments, environment: environment)
        guard output.status == 0 else {
            throw BrewClientError.commandFailed(
                command: "brew " + arguments.joined(separator: " "),
                status: output.status,
                stderr: output.standardError
            )
        }
        return output
    }

    /// Keeps brew quiet and machine-friendly, and guarantees its own bin dir
    /// is on PATH (GUI apps inherit a minimal launchd environment).
    private nonisolated var environment: [String: String] {
        [
            "PATH": "\(brewURL.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin",
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
            "HOMEBREW_NO_EMOJI": "1",
            "HOMEBREW_COLOR": "0",
            "NO_COLOR": "1",
            "TERM": "dumb",
        ]
    }
}

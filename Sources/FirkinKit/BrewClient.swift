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
    case install(BrewPackage)
    /// Install a cask while taking ownership of the already-present app
    /// (`brew install --cask --adopt`).
    case adopt(BrewPackage)
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

    /// Everything currently installed, plus which .app bundles each installed
    /// cask owns (from its artifacts) — used to match apps on disk to casks.
    public struct InstalledSnapshot: Sendable {
        public let packages: [BrewPackage]
        /// Installed cask token → the .app bundle names its artifacts declare.
        public let caskApps: [String: [String]]

        public init(packages: [BrewPackage], caskApps: [String: [String]]) {
            self.packages = packages
            self.caskApps = caskApps
        }
    }

    public func installedSnapshot() async throws -> InstalledSnapshot {
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
        let installedCasks = response.casks.filter { $0.installed != nil }
        let packages = (formulae + installedCasks.map(BrewPackage.init)).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        let caskApps = Dictionary(
            installedCasks.map { ($0.token, $0.appBundleNames) },
            uniquingKeysWith: { first, _ in first }
        )
        return InstalledSnapshot(packages: packages, caskApps: caskApps)
    }

    /// Everything currently installed, formulae and casks, sorted by name.
    public func installedPackages() async throws -> [BrewPackage] {
        try await installedSnapshot().packages
    }

    /// All cask tokens in brew's local index. brew keeps this list cached on
    /// disk, so the call is fast (~0.1s warm).
    public func allCaskTokens() async throws -> Set<String> {
        let output = try await runChecked(["casks"])
        return Set(
            output.standardOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    /// Catalog details for cask tokens. Every token must exist — one unknown
    /// token fails the whole brew call — so validate via `allCaskTokens()`.
    public func caskDetails(tokens: [String]) async throws -> [BrewPackage] {
        try await details(kind: .cask, names: tokens)
    }

    // MARK: Search

    /// How many results of each kind a search fetches details for.
    public static let searchResultLimit = 25

    /// Searches the whole Homebrew catalog by name and returns detailed
    /// results — installed packages included, so callers can show state.
    /// Formula and cask searches run concurrently, as do the detail fetches.
    public func search(_ query: String) async throws -> [BrewPackage] {
        async let formulaSearch = ProcessRunner.run(
            brewURL, arguments: ["search", "--formula", "--", query], environment: environment)
        async let caskSearch = ProcessRunner.run(
            brewURL, arguments: ["search", "--cask", "--", query], environment: environment)
        let formulaNames = try Self.searchNames(from: try await formulaSearch, command: "brew search --formula \(query)")
        let caskNames = try Self.searchNames(from: try await caskSearch, command: "brew search --cask \(query)")

        async let formulae = details(kind: .formula, names: Array(formulaNames.prefix(Self.searchResultLimit)))
        async let casks = details(kind: .cask, names: Array(caskNames.prefix(Self.searchResultLimit)))
        let results = try await formulae + (try await casks)
        return BrewSearch.ranked(results, query: query)
    }

    /// "No formulae or casks found" is an empty result, not a failure.
    private static func searchNames(from output: ProcessOutput, command: String) throws -> [String] {
        guard output.status == 0 else {
            if (output.standardError + output.standardOutput).contains("No formulae or casks found") {
                return []
            }
            throw BrewClientError.commandFailed(
                command: command, status: output.status, stderr: output.standardError)
        }
        return BrewSearch.names(from: output.standardOutput)
    }

    private func details(kind: PackageKind, names: [String]) async throws -> [BrewPackage] {
        guard !names.isEmpty else { return [] }
        let kindFlag = kind == .cask ? "--cask" : "--formula"
        let output: ProcessOutput
        do {
            output = try await runChecked(["info", "--json=v2", kindFlag] + names)
        } catch {
            // One stale index entry can fail the whole info batch; degrade to
            // bare names rather than failing the search.
            return names.map { BrewPackage(kind: kind, name: $0, displayName: $0) }
        }
        let response: BrewInfoResponse
        do {
            response = try BrewInfoResponse.decode(from: Data(output.standardOutput.utf8))
        } catch {
            throw BrewClientError.decodingFailed(underlying: error)
        }
        return kind == .cask
            ? response.casks.map(BrewPackage.init)
            : response.formulae.map(BrewPackage.init)
    }

    // MARK: Actions

    public nonisolated func arguments(for action: BrewAction) -> [String] {
        switch action {
        case .update:
            return ["update"]
        case .upgradeAll:
            return ["upgrade"]
        case let .install(package):
            return ["install", package.kind == .cask ? "--cask" : "--formula", package.name]
        case let .adopt(package):
            return ["install", "--cask", "--adopt", package.name]
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

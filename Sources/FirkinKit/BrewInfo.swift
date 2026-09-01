import Foundation

/// Mirrors the parts of `brew info --json=v2` that Firkin consumes.
/// Everything beyond the identifying key is optional, so schema drift between
/// Homebrew releases degrades gracefully instead of failing the whole decode.
public struct BrewInfoResponse: Decodable {
    public let formulae: [FormulaInfo]
    public let casks: [CaskInfo]

    public static func decode(from data: Data) throws -> BrewInfoResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(BrewInfoResponse.self, from: data)
    }
}

public struct FormulaInfo: Decodable {
    public struct Versions: Decodable {
        public let stable: String?
    }

    public struct InstalledEntry: Decodable {
        public let version: String?
        // Homebrew emits null here for packages installed before it tracked this.
        public let installedAsDependency: Bool?
        public let installedOnRequest: Bool?
    }

    public let name: String
    public let fullName: String?
    public let tap: String?
    public let desc: String?
    public let license: String?
    public let homepage: String?
    public let versions: Versions?
    public let installed: [InstalledEntry]?
    public let outdated: Bool?
    public let pinned: Bool?
    public let deprecated: Bool?
}

public struct CaskInfo: Decodable {
    public let token: String
    public let fullToken: String?
    public let tap: String?
    /// Display names; can be empty (e.g. casks from a since-removed tap).
    public let name: [String]?
    public let desc: String?
    public let homepage: String?
    public let version: String?
    /// Installed version string; nil when the cask is not installed.
    public let installed: String?
    public let outdated: Bool?
    public let autoUpdates: Bool?
    public let deprecated: Bool?
    public let pinned: Bool?
    public let artifacts: [CaskArtifact]?

    /// The .app bundle names this cask installs, e.g. ["Firefox.app"].
    public var appBundleNames: [String] {
        artifacts?.compactMap(\.app).flatMap { $0 } ?? []
    }
}

/// One entry of a cask's `artifacts` array. Only the `app` key matters to
/// Firkin; every other artifact kind (uninstall, zap, binary, …) is ignored,
/// as are non-string app entries like {"target": …} rename forms.
public struct CaskArtifact: Decodable {
    public let app: [String]?

    private struct AppEntry: Decodable {
        let name: String?
        init(from decoder: Decoder) throws {
            name = try? decoder.singleValueContainer().decode(String.self)
        }
    }

    private enum CodingKeys: String, CodingKey { case app }

    public init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        app = (try? container?.decode([AppEntry].self, forKey: .app))?
            .map { $0.compactMap(\.name) }
    }
}

public extension BrewPackage {
    init(_ formula: FormulaInfo) {
        // One entry per installed keg; the newest is last.
        let current = formula.installed?.last
        self.init(
            kind: .formula,
            name: formula.name,
            displayName: formula.fullName ?? formula.name,
            summary: formula.desc,
            homepage: formula.homepage.flatMap(URL.init(string:)),
            tap: formula.tap,
            license: formula.license,
            installedVersion: current?.version,
            latestVersion: formula.versions?.stable,
            isOutdated: formula.outdated ?? false,
            isPinned: formula.pinned ?? false,
            isDeprecated: formula.deprecated ?? false,
            isInstalledAsDependency: (current?.installedAsDependency ?? false)
                || current?.installedOnRequest == false,
            autoUpdates: false
        )
    }

    init(_ cask: CaskInfo) {
        self.init(
            kind: .cask,
            name: cask.token,
            displayName: cask.name?.first(where: { !$0.isEmpty }) ?? cask.token,
            summary: cask.desc,
            homepage: cask.homepage.flatMap(URL.init(string:)),
            tap: cask.tap,
            license: nil,
            installedVersion: cask.installed,
            latestVersion: cask.version,
            isOutdated: cask.outdated ?? false,
            isPinned: cask.pinned ?? false,
            isDeprecated: cask.deprecated ?? false,
            isInstalledAsDependency: false,
            autoUpdates: cask.autoUpdates ?? false
        )
    }
}

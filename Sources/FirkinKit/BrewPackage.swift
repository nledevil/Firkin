import Foundation

public enum PackageKind: String, Codable, Hashable, Sendable, CaseIterable {
    case formula
    case cask

    public var label: String {
        switch self {
        case .formula: return "Formula"
        case .cask: return "Cask"
        }
    }
}

/// One installed Homebrew package, unified across formulae and casks.
public struct BrewPackage: Identifiable, Hashable, Sendable {
    public let kind: PackageKind
    /// Formula name or cask token — what `brew` commands take as an argument.
    public let name: String
    /// Human-readable name; casks provide one, formulae fall back to `name`.
    public let displayName: String
    public let summary: String?
    public let homepage: URL?
    public let tap: String?
    public let license: String?
    public let installedVersion: String?
    public let latestVersion: String?
    public let isOutdated: Bool
    public let isPinned: Bool
    public let isDeprecated: Bool
    public let isInstalledAsDependency: Bool
    /// Casks that update themselves; `brew upgrade` skips them unless greedy.
    public let autoUpdates: Bool

    public var id: String { "\(kind.rawValue):\(name)" }

    /// Search results carry catalog entries too; installed state is simply
    /// whether brew reported an installed version.
    public var isInstalled: Bool { installedVersion != nil }

    /// Cask versions may append a build after a comma ("155.0,abc123");
    /// this is the human part, comparable to an app bundle's version.
    public var normalizedLatestVersion: String? {
        latestVersion?.split(separator: ",").first.map(String.init)
    }

    public init(
        kind: PackageKind,
        name: String,
        displayName: String,
        summary: String? = nil,
        homepage: URL? = nil,
        tap: String? = nil,
        license: String? = nil,
        installedVersion: String? = nil,
        latestVersion: String? = nil,
        isOutdated: Bool = false,
        isPinned: Bool = false,
        isDeprecated: Bool = false,
        isInstalledAsDependency: Bool = false,
        autoUpdates: Bool = false
    ) {
        self.kind = kind
        self.name = name
        self.displayName = displayName
        self.summary = summary
        self.homepage = homepage
        self.tap = tap
        self.license = license
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.isOutdated = isOutdated
        self.isPinned = isPinned
        self.isDeprecated = isDeprecated
        self.isInstalledAsDependency = isInstalledAsDependency
        self.autoUpdates = autoUpdates
    }
}

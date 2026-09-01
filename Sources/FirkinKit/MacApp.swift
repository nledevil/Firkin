import Foundation

/// CPU architecture support of an app bundle's main executable.
public enum AppArchitecture: String, Hashable, Sendable {
    /// arm64 only.
    case appleSilicon
    /// arm64 and x86_64.
    case universal
    /// x86_64 only — runs under Rosetta 2 on Apple Silicon.
    case intel
    case unknown

    public static func classify(architectures: [Int]) -> AppArchitecture {
        let hasARM = architectures.contains(NSBundleExecutableArchitectureARM64)
        let hasIntel = architectures.contains(NSBundleExecutableArchitectureX86_64)
        switch (hasARM, hasIntel) {
        case (true, true): return .universal
        case (true, false): return .appleSilicon
        case (false, true): return .intel
        case (false, false): return .unknown
        }
    }

    /// Whether an app of this architecture needs Rosetta 2 translation.
    public func requiresRosetta(onAppleSiliconMac: Bool = ProcessInfo.isAppleSiliconMac) -> Bool {
        onAppleSiliconMac && self == .intel
    }
}

public extension ProcessInfo {
    /// True on arm64 hardware, even if the current process runs translated.
    static let isAppleSiliconMac: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }()
}

/// A macOS application bundle found on disk.
public struct MacApp: Identifiable, Hashable, Sendable {
    public let url: URL
    /// The bundle's file name without the .app extension.
    public let name: String
    public let bundleID: String?
    public let version: String?
    public let architecture: AppArchitecture

    public var id: String { url.path }
    public var bundleFileName: String { url.lastPathComponent }

    public init(url: URL, name: String, bundleID: String?, version: String?, architecture: AppArchitecture) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.architecture = architecture
    }

    /// Best-effort guess of the Homebrew cask token for an app name, following
    /// the cask naming convention: lowercase, non-token characters hyphenated.
    /// Guesses are only used after validating against brew's real token list.
    public static func caskTokenGuess(forAppNamed name: String) -> String {
        var base = name
        if base.lowercased().hasSuffix(".app") { base = String(base.dropLast(4)) }
        var token = ""
        for character in base.lowercased() {
            if character.isLetter || character.isNumber || character == "+" || character == "@" {
                token.append(character)
            } else if !token.isEmpty && !token.hasSuffix("-") {
                token.append("-")
            }
        }
        while token.hasSuffix("-") { token.removeLast() }
        return token
    }
}

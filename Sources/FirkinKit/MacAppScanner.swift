import Foundation

/// Finds .app bundles on disk and reads their identity, version, and
/// executable architectures.
public enum MacAppScanner {
    public static var defaultDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    /// Scans the top level of each directory for .app bundles.
    public static func scan(directories: [URL] = defaultDirectories) -> [MacApp] {
        let fileManager = FileManager.default
        var apps: [MacApp] = []
        for directory in directories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                if let app = inspect(appAt: entry) {
                    apps.append(app)
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads one app bundle. Returns nil for bundles without a readable
    /// Info.plist (broken or still-downloading apps).
    public static func inspect(appAt url: URL) -> MacApp? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        // Architectures come from NSBundle, which parses the Mach-O header
        // (including fat binaries) for us.
        let architectures = (Bundle(url: url)?.executableArchitectures ?? []).map(\.intValue)
        return MacApp(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            bundleID: plist["CFBundleIdentifier"] as? String,
            version: (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String),
            architecture: .classify(architectures: architectures)
        )
    }
}

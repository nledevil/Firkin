import Foundation

/// Finds .app bundles on disk and reads their identity, version, and
/// executable architectures.
public enum MacAppScanner {
    /// The same domains Finder's Applications view merges: local, system
    /// (plus the cryptex mount where Safari lives on modern macOS), and user.
    public static var defaultDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    /// Scans each directory for .app bundles, descending one level into
    /// plain subfolders (Utilities, Setapp, vendor folders) but never into
    /// app bundles themselves — nested helper apps aren't user-facing.
    public static func scan(directories: [URL] = defaultDirectories) -> [MacApp] {
        let fileManager = FileManager.default
        var apps: [MacApp] = []
        for directory in directories {
            for entry in contents(of: directory, fileManager: fileManager) {
                if entry.pathExtension == "app" {
                    if let app = inspect(appAt: entry) {
                        apps.append(app)
                    }
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    for nested in contents(of: entry, fileManager: fileManager) where nested.pathExtension == "app" {
                        if let app = inspect(appAt: nested) {
                            apps.append(app)
                        }
                    }
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func contents(of directory: URL, fileManager: FileManager) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
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

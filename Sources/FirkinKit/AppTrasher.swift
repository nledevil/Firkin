import Foundation

public enum AppTrasherError: Error, LocalizedError {
    /// The user dismissed the system authorization dialog.
    case canceled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .canceled: return "The authorization dialog was canceled."
        case let .failed(message): return message
        }
    }
}

/// Uninstall path for apps Homebrew doesn't manage: move the bundle to the
/// user's Trash, so the action stays reversible.
public enum AppTrasher {
    /// Moves the item to the Trash and returns its new location there.
    /// Throws when the user lacks permission (e.g. root-owned app bundles) —
    /// callers can escalate via `trashWithAdministratorPrivileges`.
    @discardableResult
    public static func trash(appAt url: URL) throws -> URL? {
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        return trashedURL as URL?
    }

    /// Moves an app to the user's Trash with administrator rights, for
    /// bundles the user cannot delete directly. macOS presents its own
    /// password dialog (osascript's "with administrator privileges") — the
    /// password never passes through Firkin. The move keeps the app in the
    /// Trash (chowned back to the user) so the action stays reversible.
    /// Returns the app's new location.
    @discardableResult
    public static func trashWithAdministratorPrivileges(appAt url: URL, now: Date = Date()) async throws -> URL {
        let destination = privilegedTrashDestination(for: url, at: now)
        let script = privilegedTrashScript(moving: url, to: destination, uid: getuid(), gid: getgid())
        let output = try await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script]
        )
        guard output.status == 0 else {
            if output.standardError.contains("-128") {
                throw AppTrasherError.canceled
            }
            throw AppTrasherError.failed(
                output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return destination
    }

    /// Finder-style unique destination in the user's Trash ("Name 14.32.05.app"),
    /// so no existing Trash item can be clobbered and the Trash never needs
    /// to be read (reading ~/.Trash is TCC-restricted).
    static func privilegedTrashDestination(for url: URL, at date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH.mm.ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let name = ext.isEmpty
            ? "\(base) \(formatter.string(from: date))"
            : "\(base) \(formatter.string(from: date)).\(ext)"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash")
            .appendingPathComponent(name)
    }

    /// The AppleScript for the privileged move — pure, so tests can verify
    /// the quoting. The shell command moves the bundle into the Trash and
    /// returns ownership to the user so they can restore or empty it.
    static func privilegedTrashScript(moving source: URL, to destination: URL, uid: uid_t, gid: gid_t) -> String {
        let command = "/bin/mv \(shellQuoted(source.path)) \(shellQuoted(destination.path))"
            + " && /usr/sbin/chown -R \(uid):\(gid) \(shellQuoted(destination.path))"
        return "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

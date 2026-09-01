import Foundation

/// Uninstall path for apps Homebrew doesn't manage: move the bundle to the
/// user's Trash, so the action stays reversible.
public enum AppTrasher {
    /// Moves the item to the Trash and returns its new location there.
    /// Throws when the user lacks permission (e.g. system-protected apps) —
    /// callers should surface the error and suggest Finder.
    @discardableResult
    public static func trash(appAt url: URL) throws -> URL? {
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        return trashedURL as URL?
    }
}

import Foundation

/// Parsing and ranking helpers for `brew search` output. Pure functions so
/// they stay unit-testable without running brew.
public enum BrewSearch {
    /// Extracts package names from single-kind `brew search` output: one name
    /// per line, ignoring blanks and Error/Warning chatter. (Piped brew 6
    /// output has no section headers, which is why searches are run per kind.)
    public static func names(from output: String) -> [String] {
        output.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  !line.hasPrefix("==>"),
                  !line.hasPrefix("Error:"),
                  !line.hasPrefix("Warning:") else { return nil }
            // Keep only the name token in case brew ever appends markers the
            // way its tty output does.
            return line.split(separator: " ").first.map(String.init)
        }
    }

    /// Orders results by how well they match the query: exact name, then
    /// prefix, then substring, then the rest — stable within each rank.
    public static func ranked(_ results: [BrewPackage], query: String) -> [BrewPackage] {
        let needle = query.lowercased()
        func rank(_ package: BrewPackage) -> Int {
            let candidates = [package.name.lowercased(), package.displayName.lowercased()]
            if candidates.contains(needle) { return 0 }
            if candidates.contains(where: { $0.hasPrefix(needle) }) { return 1 }
            if candidates.contains(where: { $0.contains(needle) }) { return 2 }
            return 3
        }
        return results.enumerated()
            .sorted { lhs, rhs in
                let left = rank(lhs.element)
                let right = rank(rhs.element)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }
}

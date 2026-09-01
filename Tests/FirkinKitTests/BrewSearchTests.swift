import Testing
@testable import FirkinKit

private func result(_ name: String, display: String? = nil, kind: PackageKind = .formula, installed: String? = nil) -> BrewPackage {
    BrewPackage(kind: kind, name: name, displayName: display ?? name, installedVersion: installed)
}

@Test func parsesSearchOutputLines() {
    let output = """
    wget
    wget2
      wgetpaste

    Warning: some chatter
    Error: nothing here
    """
    #expect(BrewSearch.names(from: output) == ["wget", "wget2", "wgetpaste"])
}

@Test func parserStripsTrailingMarkers() {
    #expect(BrewSearch.names(from: "wget \u{2714}\n") == ["wget"])
}

@Test func rankingPutsExactThenPrefixThenSubstring() {
    let ranked = BrewSearch.ranked([
        result("awget"),        // substring
        result("wget2"),        // prefix
        result("unrelated"),    // no match in name…
        result("wget"),         // exact
    ], query: "wget")
    #expect(ranked.map(\.name) == ["wget", "wget2", "awget", "unrelated"])
}

@Test func rankingMatchesDisplayNameAndIsStableWithinRank() {
    let ranked = BrewSearch.ranked([
        result("zzz-tool", display: "Firefox Helper"), // display-name prefix
        result("bbb", display: "also firefox thing"),  // display-name substring
        result("aaa", display: "another firefox"),     // display-name substring, later rank ties keep order
        result("firefox", display: "Mozilla Firefox", kind: .cask), // exact token
    ], query: "firefox")
    #expect(ranked.map(\.name) == ["firefox", "zzz-tool", "bbb", "aaa"])
}

@Test func installedStateComesFromVersionPresence() {
    #expect(result("jq", installed: "1.7").isInstalled)
    #expect(!result("jq").isInstalled)
}

@Test func installActionArguments() throws {
    let client = try? BrewClient()
    guard let client else { return } // machine without Homebrew
    let formula = BrewPackage(kind: .formula, name: "wget", displayName: "wget")
    let cask = BrewPackage(kind: .cask, name: "firefox", displayName: "Firefox")
    #expect(client.arguments(for: .install(formula)) == ["install", "--formula", "wget"])
    #expect(client.arguments(for: .install(cask)) == ["install", "--cask", "firefox"])
}

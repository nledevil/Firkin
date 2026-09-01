import Foundation
import Testing
@testable import FirkinKit

@Test func classifiesArchitectures() {
    let arm = NSBundleExecutableArchitectureARM64
    let intel = NSBundleExecutableArchitectureX86_64
    #expect(AppArchitecture.classify(architectures: [arm]) == .appleSilicon)
    #expect(AppArchitecture.classify(architectures: [arm, intel]) == .universal)
    #expect(AppArchitecture.classify(architectures: [intel]) == .intel)
    #expect(AppArchitecture.classify(architectures: []) == .unknown)
}

@Test func rosettaOnlyForIntelBinariesOnAppleSilicon() {
    #expect(AppArchitecture.intel.requiresRosetta(onAppleSiliconMac: true))
    #expect(!AppArchitecture.intel.requiresRosetta(onAppleSiliconMac: false))
    #expect(!AppArchitecture.universal.requiresRosetta(onAppleSiliconMac: true))
    #expect(!AppArchitecture.appleSilicon.requiresRosetta(onAppleSiliconMac: true))
}

@Test func guessesCaskTokensFromAppNames() {
    #expect(MacApp.caskTokenGuess(forAppNamed: "Firefox.app") == "firefox")
    #expect(MacApp.caskTokenGuess(forAppNamed: "Google Chrome") == "google-chrome")
    #expect(MacApp.caskTokenGuess(forAppNamed: "Visual Studio Code") == "visual-studio-code")
    #expect(MacApp.caskTokenGuess(forAppNamed: "1Password 7") == "1password-7")
    #expect(MacApp.caskTokenGuess(forAppNamed: "  Weird -- Name!  ") == "weird-name")
}

@Test func normalizesCaskVersionsWithBuildSuffix() {
    let withBuild = BrewPackage(kind: .cask, name: "x", displayName: "x", latestVersion: "155.0,abc123")
    let plain = BrewPackage(kind: .cask, name: "y", displayName: "y", latestVersion: "2.1")
    #expect(withBuild.normalizedLatestVersion == "155.0")
    #expect(plain.normalizedLatestVersion == "2.1")
    #expect(BrewPackage(kind: .cask, name: "z", displayName: "z").normalizedLatestVersion == nil)
}

@Test func decodesCaskArtifactsAppNames() throws {
    let json = Data("""
    {
      "formulae": [],
      "casks": [
        {
          "token": "firefox",
          "version": "155.0",
          "installed": "155.0",
          "artifacts": [
            {"uninstall": [{"quit": "org.mozilla.firefox"}]},
            {"app": ["Firefox.app", {"target": "Renamed.app"}]},
            {"zap": [{"trash": ["~/Library/Caches/Firefox"]}]}
          ]
        }
      ]
    }
    """.utf8)
    let response = try BrewInfoResponse.decode(from: json)
    #expect(response.casks[0].appBundleNames == ["Firefox.app"])
}

@Test func systemAppDetectionByPath() {
    let system = MacApp(
        url: URL(fileURLWithPath: "/System/Applications/Mail.app"),
        name: "Mail", bundleID: nil, version: nil, architecture: .universal)
    let cryptex = MacApp(
        url: URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications/Safari.app"),
        name: "Safari", bundleID: nil, version: nil, architecture: .universal)
    let regular = MacApp(
        url: URL(fileURLWithPath: "/Applications/Firefox.app"),
        name: "Firefox", bundleID: nil, version: nil, architecture: .universal)
    #expect(system.isSystemApp)
    #expect(cryptex.isSystemApp)
    #expect(!regular.isSystemApp)
}

@Test func scannerFindsAppsOneLevelDeepButNotDeeper() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("FirkinScanTest-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: root) }

    func makeApp(at url: URL, bundleID: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try fileManager.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleShortVersionString": "1.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    try makeApp(at: root.appendingPathComponent("Top.app"), bundleID: "test.top")
    try makeApp(at: root.appendingPathComponent("Utilities/Nested.app"), bundleID: "test.nested")
    try makeApp(at: root.appendingPathComponent("Utilities/Deeper/TooDeep.app"), bundleID: "test.toodeep")

    let apps = MacAppScanner.scan(directories: [root])
    #expect(apps.map(\.name).sorted() == ["Nested", "Top"])
    #expect(apps.allSatisfy { $0.version == "1.0" })
}

@Test func trashMovesBundleToTrash() throws {
    let fileManager = FileManager.default
    let bundle = fileManager.temporaryDirectory
        .appendingPathComponent("FirkinTrashTest-\(UUID().uuidString).app")
    try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)

    let trashed = try AppTrasher.trash(appAt: bundle)

    #expect(!fileManager.fileExists(atPath: bundle.path))
    let trashedURL = try #require(trashed)
    #expect(fileManager.fileExists(atPath: trashedURL.path))
    try? fileManager.removeItem(at: trashedURL) // clean our own item out of the Trash
}

@Test func shellQuotingNeutralizesSingleQuotes() {
    #expect(AppTrasher.shellQuoted("/Applications/Plain.app") == "'/Applications/Plain.app'")
    // A name like it's.app must not break out of the quoted argument.
    #expect(AppTrasher.shellQuoted("/Applications/it's.app") == "'/Applications/it'\\''s.app'")
}

@Test func appleScriptEscapingHandlesQuotesAndBackslashes() {
    #expect(AppTrasher.appleScriptEscaped(#"say "hi" \ bye"#) == #"say \"hi\" \\ bye"#)
}

@Test func privilegedTrashScriptComposition() {
    let source = URL(fileURLWithPath: "/Applications/Some App.app")
    let destination = URL(fileURLWithPath: "/Users/me/.Trash/Some App 14.32.05.app")
    let script = AppTrasher.privilegedTrashScript(moving: source, to: destination, uid: 501, gid: 20)
    #expect(script.hasPrefix("do shell script \""))
    #expect(script.hasSuffix("\" with administrator privileges"))
    #expect(script.contains("/bin/mv '/Applications/Some App.app' '/Users/me/.Trash/Some App 14.32.05.app'"))
    #expect(script.contains("/usr/sbin/chown -R 501:20 '/Users/me/.Trash/Some App 14.32.05.app'"))
}

@Test func privilegedTrashDestinationIsTimestampedInUserTrash() {
    let date = Date(timeIntervalSince1970: 0)
    let url = AppTrasher.privilegedTrashDestination(
        for: URL(fileURLWithPath: "/Applications/Thing.app"), at: date)
    #expect(url.path.contains("/.Trash/"))
    #expect(url.lastPathComponent.hasPrefix("Thing "))
    #expect(url.pathExtension == "app")
}

@Test func adoptActionArguments() throws {
    let client = try? BrewClient()
    guard let client else { return } // machine without Homebrew
    let cask = BrewPackage(kind: .cask, name: "firefox", displayName: "Firefox")
    #expect(client.arguments(for: .adopt(cask)) == ["install", "--cask", "--adopt", "firefox"])
}

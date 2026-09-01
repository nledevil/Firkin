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

@Test func adoptActionArguments() throws {
    let client = try? BrewClient()
    guard let client else { return } // machine without Homebrew
    let cask = BrewPackage(kind: .cask, name: "firefox", displayName: "Firefox")
    #expect(client.arguments(for: .adopt(cask)) == ["install", "--cask", "--adopt", "firefox"])
}

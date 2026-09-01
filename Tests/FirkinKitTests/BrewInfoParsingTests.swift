import Foundation
import Testing
@testable import FirkinKit

// Trimmed from real `brew info --json=v2 --installed` output (Homebrew 6.0),
// keeping the awkward cases: null installed_as_dependency, a cask with a null
// tap and an empty name array, and unknown keys that must be ignored.
private let sampleJSON = Data("""
{
  "formulae": [
    {
      "name": "autoconf",
      "full_name": "autoconf",
      "tap": "homebrew/core",
      "desc": "Automatic configure script builder",
      "license": "GPL-3.0-or-later",
      "homepage": "https://www.gnu.org/software/autoconf/",
      "versions": { "stable": "2.73", "head": null, "bottle": true },
      "installed": [
        {
          "version": "2.72",
          "installed_as_dependency": null,
          "installed_on_request": false
        }
      ],
      "outdated": true,
      "pinned": false,
      "deprecated": false,
      "keg_only": false,
      "some_future_key": { "nested": [1, 2, 3] }
    },
    {
      "name": "git",
      "full_name": "git",
      "tap": "homebrew/core",
      "desc": "Distributed revision control system",
      "license": "GPL-2.0-only",
      "homepage": "https://git-scm.com",
      "versions": { "stable": "2.51.0" },
      "installed": [
        {
          "version": "2.51.0",
          "installed_as_dependency": false,
          "installed_on_request": true
        }
      ],
      "outdated": false,
      "pinned": true,
      "deprecated": false
    },
    {
      "name": "not-installed",
      "versions": { "stable": "1.0.0" },
      "installed": []
    }
  ],
  "casks": [
    {
      "token": "codexbar",
      "full_token": "codexbar",
      "tap": null,
      "name": [],
      "desc": null,
      "homepage": null,
      "version": "0.17.0",
      "installed": "0.17.0",
      "outdated": false,
      "auto_updates": null,
      "deprecated": false,
      "pinned": false
    },
    {
      "token": "firefox",
      "full_token": "firefox",
      "tap": "homebrew/cask",
      "name": ["Mozilla Firefox"],
      "desc": "Web browser",
      "homepage": "https://www.mozilla.org/firefox/",
      "version": "142.0",
      "installed": "141.0",
      "outdated": true,
      "auto_updates": true,
      "deprecated": false,
      "pinned": false
    }
  ]
}
""".utf8)

private func installedPackages(from data: Data) throws -> [BrewPackage] {
    let response = try BrewInfoResponse.decode(from: data)
    let formulae = response.formulae
        .filter { !($0.installed?.isEmpty ?? true) }
        .map(BrewPackage.init)
    let casks = response.casks
        .filter { $0.installed != nil }
        .map(BrewPackage.init)
    return formulae + casks
}

@Test func decodesFormulaeAndCasksIgnoringUnknownKeys() throws {
    let response = try BrewInfoResponse.decode(from: sampleJSON)
    #expect(response.formulae.count == 3)
    #expect(response.casks.count == 2)
}

@Test func skipsEntriesThatAreNotInstalled() throws {
    let packages = try installedPackages(from: sampleJSON)
    #expect(packages.count == 4)
    #expect(!packages.contains { $0.name == "not-installed" })
}

@Test func mapsOutdatedDependencyFormula() throws {
    let packages = try installedPackages(from: sampleJSON)
    let autoconf = try #require(packages.first { $0.name == "autoconf" })
    #expect(autoconf.kind == .formula)
    #expect(autoconf.installedVersion == "2.72")
    #expect(autoconf.latestVersion == "2.73")
    #expect(autoconf.isOutdated)
    // installed_as_dependency is null, but installed_on_request == false
    // still marks it as a dependency.
    #expect(autoconf.isInstalledAsDependency)
}

@Test func mapsRequestedPinnedFormula() throws {
    let packages = try installedPackages(from: sampleJSON)
    let git = try #require(packages.first { $0.name == "git" })
    #expect(!git.isInstalledAsDependency)
    #expect(git.isPinned)
    #expect(!git.isOutdated)
    #expect(git.homepage?.absoluteString == "https://git-scm.com")
}

@Test func caskWithEmptyNameFallsBackToToken() throws {
    let packages = try installedPackages(from: sampleJSON)
    let codexbar = try #require(packages.first { $0.name == "codexbar" })
    #expect(codexbar.kind == .cask)
    #expect(codexbar.displayName == "codexbar")
    #expect(codexbar.tap == nil)
    #expect(!codexbar.autoUpdates)
}

@Test func caskUsesFirstNameAndAutoUpdateFlag() throws {
    let packages = try installedPackages(from: sampleJSON)
    let firefox = try #require(packages.first { $0.name == "firefox" })
    #expect(firefox.displayName == "Mozilla Firefox")
    #expect(firefox.installedVersion == "141.0")
    #expect(firefox.latestVersion == "142.0")
    #expect(firefox.isOutdated)
    #expect(firefox.autoUpdates)
}

@Test func actionArgumentsDistinguishFormulaeAndCasks() throws {
    let client = try? BrewClient()
    guard let client else { return } // machine without Homebrew
    let formula = BrewPackage(kind: .formula, name: "git", displayName: "git")
    let cask = BrewPackage(kind: .cask, name: "firefox", displayName: "Firefox")
    #expect(client.arguments(for: .upgrade(formula)) == ["upgrade", "--formula", "git"])
    #expect(client.arguments(for: .upgrade(cask)) == ["upgrade", "--cask", "firefox"])
    #expect(client.arguments(for: .uninstall(cask)) == ["uninstall", "--cask", "firefox"])
    #expect(client.arguments(for: .update) == ["update"])
}

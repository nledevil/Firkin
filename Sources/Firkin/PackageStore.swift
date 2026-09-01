import SwiftUI
import Observation
import FirkinKit

@MainActor
@Observable
final class PackageStore {
    enum SidebarSection: String, CaseIterable, Identifiable {
        case all, formulae, casks, outdated, browse, apps

        static let librarySections: [SidebarSection] = [.all, .formulae, .casks, .outdated]

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All Packages"
            case .formulae: return "Formulae"
            case .casks: return "Casks"
            case .outdated: return "Outdated"
            case .browse: return "Browse"
            case .apps: return "Applications"
            }
        }

        var systemImage: String {
            switch self {
            case .all: return "shippingbox"
            case .formulae: return "terminal"
            case .casks: return "macwindow"
            case .outdated: return "arrow.up.circle"
            case .browse: return "magnifyingglass"
            case .apps: return "square.grid.2x2"
            }
        }
    }

    /// How an app on disk relates to Homebrew.
    enum AppManagement: Hashable {
        /// An installed cask owns this app.
        case managedByBrew(BrewPackage)
        /// A catalog cask matches this app, but brew doesn't manage it yet.
        case adoptable(BrewPackage)
        case unmanaged
    }

    struct AppEntry: Identifiable {
        let app: MacApp
        let management: AppManagement

        var id: String { app.id }

        var caskPackage: BrewPackage? {
            switch management {
            case let .managedByBrew(package), let .adoptable(package): return package
            case .unmanaged: return nil
            }
        }

        /// Only brew-managed apps count as updatable — brew's outdated flag is
        /// authoritative. Adoptable apps show both versions in the detail pane
        /// instead: app and cask version formats differ too often to compare
        /// mechanically (e.g. Office reports 16.112.2 vs cask 16.112.26083020
        /// for the same release).
        var updateAvailable: Bool {
            if case let .managedByBrew(package) = management {
                return package.isOutdated
            }
            return false
        }
    }

    /// A running (or just finished) brew action shown in the console sheet.
    struct Operation: Identifiable {
        let id = UUID()
        let title: String
        var log = ""
        var isRunning = true
        var failureMessage: String?
    }

    private(set) var packages: [BrewPackage] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var brewVersion: String?

    var sidebarSelection: SidebarSection? = .all {
        didSet {
            scheduleSearch()
            if sidebarSelection == .apps && !appsLoaded && !isLoadingApps {
                Task { await self.loadApps() }
            }
        }
    }
    var searchText = "" {
        didSet { scheduleSearch() }
    }
    var selectedPackageID: BrewPackage.ID?
    var activeOperation: Operation?

    // Browse (catalog search) state.
    private(set) var searchResults: [BrewPackage] = []
    private(set) var isSearching = false
    private(set) var searchError: String?
    var selectedResultID: BrewPackage.ID?
    private var searchTask: Task<Void, Never>?

    // Applications (apps on disk) state.
    private(set) var appEntries: [AppEntry] = []
    private(set) var isLoadingApps = false
    private(set) var appsLoaded = false
    private(set) var appsError: String?
    var selectedAppID: String?
    /// Set when moving an app to the Trash fails; shown as an alert that can
    /// offer to retry with administrator privileges.
    struct TrashFailure: Identifiable {
        let id = UUID()
        let entry: AppEntry
        let message: String
        let canEscalate: Bool
    }
    var trashFailure: TrashFailure?
    private var caskAppNames: [String: [String]] = [:]
    private var allCaskTokens: Set<String>?

    private var client: BrewClient?
    private var clientError: String?

    init() {
        do {
            client = try BrewClient()
        } catch {
            clientError = error.localizedDescription
        }
    }

    var effectiveSection: SidebarSection { sidebarSelection ?? .all }

    var filteredPackages: [BrewPackage] {
        var result = packages
        switch effectiveSection {
        case .browse, .apps:
            return [] // These sections have their own lists.
        case .all:
            break
        case .formulae:
            result = result.filter { $0.kind == .formula }
        case .casks:
            result = result.filter { $0.kind == .cask }
        case .outdated:
            result = result.filter(\.isOutdated)
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return result }
        return result.filter { package in
            package.name.localizedCaseInsensitiveContains(query)
                || package.displayName.localizedCaseInsensitiveContains(query)
                || (package.summary?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selectedPackage: BrewPackage? {
        selectedPackageID.flatMap { id in packages.first { $0.id == id } }
    }

    /// What the detail pane shows: a search result in Browse, an installed
    /// package everywhere else.
    var detailPackage: BrewPackage? {
        effectiveSection == .browse
            ? selectedResultID.flatMap { id in searchResults.first { $0.id == id } }
            : selectedPackage
    }

    var outdatedCount: Int {
        packages.filter(\.isOutdated).count
    }

    func count(for section: SidebarSection) -> Int {
        switch section {
        case .all: return packages.count
        case .formulae: return packages.filter { $0.kind == .formula }.count
        case .casks: return packages.filter { $0.kind == .cask }.count
        case .outdated: return outdatedCount
        case .browse: return 0 // no badge
        case .apps: return appUpdatesCount
        }
    }

    var appUpdatesCount: Int {
        appEntries.filter(\.updateAvailable).count
    }

    var filteredAppEntries: [AppEntry] {
        let query = trimmedSearchQuery
        guard !query.isEmpty else { return appEntries }
        return appEntries.filter {
            $0.app.name.localizedCaseInsensitiveContains(query)
                || ($0.app.bundleID?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var detailAppEntry: AppEntry? {
        selectedAppID.flatMap { id in appEntries.first { $0.id == id } }
    }

    var trimmedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Catalog search

    private func scheduleSearch() {
        searchTask?.cancel()
        guard effectiveSection == .browse else {
            isSearching = false
            return
        }
        let query = trimmedSearchQuery
        guard query.count >= 2 else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self.runSearch(query: query)
        }
    }

    private func runSearch(query: String) async {
        guard let client else {
            searchError = clientError
            isSearching = false
            return
        }
        do {
            let results = try await client.search(query)
            guard !Task.isCancelled else { return }
            searchResults = results
            searchError = nil
        } catch {
            guard !Task.isCancelled else { return }
            searchError = error.localizedDescription
        }
        isSearching = false
    }

    /// Uninstalls an app from disk: brew-managed apps through brew (so brew's
    /// bookkeeping stays correct), everything else by trashing the bundle.
    /// A permission failure offers escalation to administrator privileges.
    func uninstallApp(_ entry: AppEntry) async {
        if case let .managedByBrew(package) = entry.management {
            await perform(.uninstall(package))
            return
        }
        let url = entry.app.url
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try AppTrasher.trash(appAt: url)
            }.value
            selectedAppID = nil
            await loadApps()
        } catch {
            trashFailure = TrashFailure(
                entry: entry,
                message: error.localizedDescription,
                canEscalate: true
            )
        }
    }

    /// Retries a failed trash with admin rights. macOS presents its own
    /// password dialog; a canceled dialog is not an error.
    func uninstallAppWithAdminPrivileges(_ entry: AppEntry) async {
        do {
            try await AppTrasher.trashWithAdministratorPrivileges(appAt: entry.app.url)
            selectedAppID = nil
            await loadApps()
        } catch AppTrasherError.canceled {
            // The user dismissed the authorization dialog — nothing to report.
        } catch {
            trashFailure = TrashFailure(
                entry: entry,
                message: error.localizedDescription,
                canEscalate: false
            )
        }
    }

    /// Re-runs the current search immediately (no debounce) so result rows
    /// reflect a just-finished install or uninstall.
    private func refreshSearchIfBrowsing() async {
        guard effectiveSection == .browse, trimmedSearchQuery.count >= 2 else { return }
        await runSearch(query: trimmedSearchQuery)
    }

    func refresh() async {
        guard let client else {
            loadError = clientError
            return
        }
        isLoading = true
        do {
            let snapshot = try await client.installedSnapshot()
            packages = snapshot.packages
            caskAppNames = snapshot.caskApps
            loadError = nil
            if brewVersion == nil {
                brewVersion = try? await client.version()
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
        if appsLoaded {
            await loadApps()
        }
    }

    /// Scans /Applications (and ~/Applications), then matches each app to
    /// Homebrew: installed casks by their declared .app artifacts, everything
    /// else by a validated cask-token guess.
    func loadApps() async {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        appsError = nil

        let scanned = await Task.detached(priority: .userInitiated) {
            MacAppScanner.scan()
        }.value

        var ownerByBundleName: [String: String] = [:]
        for (token, names) in caskAppNames {
            for name in names {
                ownerByBundleName[name] = token
            }
        }
        let caskByToken = Dictionary(
            packages.filter { $0.kind == .cask }.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var entries: [AppEntry] = []
        var unmatched: [MacApp] = []
        for app in scanned {
            if let token = ownerByBundleName[app.bundleFileName], let package = caskByToken[token] {
                entries.append(AppEntry(app: app, management: .managedByBrew(package)))
            } else {
                unmatched.append(app)
            }
        }

        if let client, !unmatched.isEmpty {
            do {
                if allCaskTokens == nil {
                    allCaskTokens = try await client.allCaskTokens()
                }
                let knownTokens = allCaskTokens ?? []
                var guessByAppID: [String: String] = [:]
                for app in unmatched {
                    let guess = MacApp.caskTokenGuess(forAppNamed: app.name)
                    if knownTokens.contains(guess) {
                        guessByAppID[app.id] = guess
                    }
                }
                let tokens = Array(Set(guessByAppID.values).prefix(50))
                let catalog = tokens.isEmpty ? [] : try await client.caskDetails(tokens: tokens)
                let catalogByToken = Dictionary(
                    catalog.map { ($0.name, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                for app in unmatched {
                    if let token = guessByAppID[app.id], let package = catalogByToken[token] {
                        // brew can report the guessed cask installed even when
                        // artifact matching missed (renamed bundle, old cask).
                        let management: AppManagement = package.isInstalled
                            ? .managedByBrew(package)
                            : .adoptable(package)
                        entries.append(AppEntry(app: app, management: management))
                    } else {
                        entries.append(AppEntry(app: app, management: .unmanaged))
                    }
                }
            } catch {
                appsError = error.localizedDescription
                entries.append(contentsOf: unmatched.map { AppEntry(app: $0, management: .unmanaged) })
            }
        } else {
            entries.append(contentsOf: unmatched.map { AppEntry(app: $0, management: .unmanaged) })
        }

        appEntries = entries.sorted {
            $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending
        }
        appsLoaded = true
        isLoadingApps = false
    }

    /// Runs a mutating brew action with the console sheet open, then reloads.
    func perform(_ action: BrewAction) async {
        guard let client else {
            loadError = clientError
            return
        }
        guard activeOperation == nil else { return }
        activeOperation = Operation(title: Self.title(for: action))
        do {
            for try await chunk in client.stream(action) {
                activeOperation?.log += chunk
            }
            activeOperation?.isRunning = false
        } catch {
            activeOperation?.isRunning = false
            activeOperation?.failureMessage = error.localizedDescription
        }
        await refresh()
        await refreshSearchIfBrowsing()
    }

    private static func title(for action: BrewAction) -> String {
        switch action {
        case .update: return "Updating Homebrew"
        case .upgradeAll: return "Upgrading all packages"
        case let .install(package): return "Installing \(package.displayName)"
        case let .adopt(package): return "Adopting \(package.displayName) into Homebrew"
        case let .upgrade(package): return "Upgrading \(package.displayName)"
        case let .uninstall(package): return "Uninstalling \(package.displayName)"
        case let .pin(package): return "Pinning \(package.displayName)"
        case let .unpin(package): return "Unpinning \(package.displayName)"
        }
    }
}

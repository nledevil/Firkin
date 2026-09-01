import SwiftUI
import Observation
import FirkinKit

@MainActor
@Observable
final class PackageStore {
    enum SidebarSection: String, CaseIterable, Identifiable {
        case all, formulae, casks, outdated, browse

        static let librarySections: [SidebarSection] = [.all, .formulae, .casks, .outdated]

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All Packages"
            case .formulae: return "Formulae"
            case .casks: return "Casks"
            case .outdated: return "Outdated"
            case .browse: return "Browse"
            }
        }

        var systemImage: String {
            switch self {
            case .all: return "shippingbox"
            case .formulae: return "terminal"
            case .casks: return "macwindow"
            case .outdated: return "arrow.up.circle"
            case .browse: return "magnifyingglass"
            }
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
        didSet { scheduleSearch() }
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
        case .browse:
            return [] // Browse shows searchResults, not the installed list.
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
        }
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
            packages = try await client.installedPackages()
            loadError = nil
            if brewVersion == nil {
                brewVersion = try? await client.version()
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
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
        case let .upgrade(package): return "Upgrading \(package.displayName)"
        case let .uninstall(package): return "Uninstalling \(package.displayName)"
        case let .pin(package): return "Pinning \(package.displayName)"
        case let .unpin(package): return "Unpinning \(package.displayName)"
        }
    }
}

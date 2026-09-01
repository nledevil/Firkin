import SwiftUI
import FirkinKit

/// Search-driven list over the whole Homebrew catalog.
struct BrowseListView: View {
    @Environment(PackageStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedResultID) {
            ForEach(store.searchResults) { package in
                PackageRow(package: package, showsInstalledBadge: true)
                    .tag(package.id)
            }
        }
        .overlay { emptyState }
        .navigationTitle("Browse")
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        if store.isSearching { return "Searching…" }
        if store.searchResults.isEmpty { return "" }
        return "\(store.searchResults.count) results"
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.searchResults.isEmpty {
            if let error = store.searchError {
                ContentUnavailableView(
                    "Search Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if store.isSearching {
                ProgressView("Searching Homebrew…")
            } else if store.trimmedSearchQuery.count < 2 {
                ContentUnavailableView(
                    "Search Homebrew",
                    systemImage: "magnifyingglass",
                    description: Text("Find new formulae and casks to install. Type at least two characters in the search field.")
                )
            } else {
                ContentUnavailableView.search(text: store.searchText)
            }
        }
    }
}

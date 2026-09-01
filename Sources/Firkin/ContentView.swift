import SwiftUI
import FirkinKit

struct ContentView: View {
    @Environment(PackageStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
        } content: {
            PackageListView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 330)
        } detail: {
            PackageDetailView()
        }
        .searchable(text: $store.searchText, prompt: "Search installed packages")
        .toolbar {
            ToolbarItemGroup {
                if store.outdatedCount > 0 {
                    Button {
                        Task { await store.perform(.upgradeAll) }
                    } label: {
                        Label("Upgrade All", systemImage: "arrow.up.circle.fill")
                    }
                    .help("Upgrade all outdated packages (brew upgrade)")
                }
                Menu {
                    Button("Run brew update") {
                        Task { await store.perform(.update) }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)
                .help("Reload installed packages (⌘R)")
            }
        }
        .sheet(item: $store.activeOperation) { _ in
            OperationConsoleView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let error = store.loadError {
                ErrorBanner(message: error) {
                    Task { await store.refresh() }
                }
            }
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
            Button("Retry", action: retry)
        }
        .font(.callout)
        .padding(10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

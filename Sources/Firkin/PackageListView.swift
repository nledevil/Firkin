import SwiftUI
import FirkinKit

struct PackageListView: View {
    @Environment(PackageStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedPackageID) {
            ForEach(store.filteredPackages) { package in
                PackageRow(package: package)
                    .tag(package.id)
            }
        }
        .overlay { emptyState }
        .navigationTitle(store.effectiveSection.title)
        .navigationSubtitle("\(store.filteredPackages.count) packages")
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.filteredPackages.isEmpty {
            if store.isLoading && store.packages.isEmpty {
                ProgressView("Loading packages…")
            } else if !store.searchText.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            } else if store.effectiveSection == .outdated && !store.packages.isEmpty {
                ContentUnavailableView(
                    "Everything Is Up to Date",
                    systemImage: "checkmark.seal",
                    description: Text("No outdated packages. Run brew update to check for newer versions.")
                )
            } else if !store.isLoading {
                ContentUnavailableView(
                    "No Packages",
                    systemImage: "shippingbox",
                    description: Text("Nothing installed in this category yet.")
                )
            }
        }
    }
}

private struct PackageRow: View {
    let package: BrewPackage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: package.kind == .cask ? "macwindow" : "shippingbox")
                .foregroundStyle(package.kind == .cask ? .blue : .orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(package.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if package.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if package.isDeprecated {
                        Text("deprecated")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
                if let summary = package.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            versionLabel
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var versionLabel: some View {
        if package.isOutdated {
            Text("\(package.installedVersion ?? "?") → \(package.latestVersion ?? "?")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.orange)
        } else {
            Text(package.installedVersion ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

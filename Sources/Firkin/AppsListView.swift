import SwiftUI
import AppKit
import FirkinKit

/// The apps installed on this Mac, with architecture and update status.
struct AppsListView: View {
    @Environment(PackageStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedAppID) {
            ForEach(store.filteredAppEntries) { entry in
                AppRow(entry: entry)
                    .tag(entry.id)
            }
        }
        .overlay { emptyState }
        .navigationTitle("Applications")
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        guard !store.appEntries.isEmpty else { return "" }
        let updates = store.appUpdatesCount
        return updates > 0
            ? "\(store.filteredAppEntries.count) apps · \(updates) updates"
            : "\(store.filteredAppEntries.count) apps"
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.filteredAppEntries.isEmpty {
            if store.isLoadingApps {
                ProgressView("Scanning applications…")
            } else if !store.trimmedSearchQuery.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            } else {
                ContentUnavailableView(
                    "No Applications Found",
                    systemImage: "square.grid.2x2",
                    description: Text("Nothing was found in /Applications.")
                )
            }
        }
    }
}

private struct AppRow: View {
    let entry: PackageStore.AppEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.app.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if case .managedByBrew = entry.management {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Managed by Homebrew")
                    }
                }
                Text(entry.app.version ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if entry.updateAvailable, let latest = entry.caskPackage?.normalizedLatestVersion {
                Text("→ \(latest)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.orange)
            }
            ArchitectureChip(architecture: entry.app.architecture)
        }
        .padding(.vertical, 2)
    }

    private var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: entry.app.url.path)
        image.size = NSSize(width: 26, height: 26)
        return image
    }
}

struct ArchitectureChip: View {
    let architecture: AppArchitecture

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .help(helpText)
    }

    private var label: String {
        if architecture.requiresRosetta() { return "Rosetta" }
        switch architecture {
        case .appleSilicon: return "Native"
        case .universal: return "Universal"
        case .intel: return "Intel"
        case .unknown: return "?"
        }
    }

    private var tint: Color {
        if architecture.requiresRosetta() { return .orange }
        switch architecture {
        case .appleSilicon, .universal: return .green
        case .intel: return .blue
        case .unknown: return .secondary
        }
    }

    private var helpText: String {
        if architecture.requiresRosetta() {
            return "Intel-only binary — runs under Rosetta 2 translation on this Mac"
        }
        switch architecture {
        case .appleSilicon: return "Apple Silicon (arm64) binary"
        case .universal: return "Universal binary (arm64 + x86_64)"
        case .intel: return "Intel (x86_64) binary"
        case .unknown: return "Could not determine the binary's architecture"
        }
    }
}

import SwiftUI
import FirkinKit

struct PackageDetailView: View {
    @Environment(PackageStore.self) private var store
    @State private var confirmingUninstall = false

    var body: some View {
        if let package = store.selectedPackage {
            detail(for: package)
        } else {
            ContentUnavailableView(
                "No Package Selected",
                systemImage: "shippingbox",
                description: Text("Choose a package from the list to see its details.")
            )
        }
    }

    private func detail(for package: BrewPackage) -> some View {
        VStack(spacing: 0) {
            header(for: package)
            Divider()
            Form {
                if let summary = package.summary {
                    Section {
                        Text(summary)
                    }
                }
                Section("Details") {
                    LabeledContent("Installed", value: package.installedVersion ?? "—")
                    LabeledContent("Latest", value: package.latestVersion ?? "—")
                    if package.autoUpdates {
                        LabeledContent("Updates", value: "App updates itself")
                    }
                    if let tap = package.tap {
                        LabeledContent("Tap", value: tap)
                    }
                    if let license = package.license {
                        LabeledContent("License", value: license)
                    }
                    if let homepage = package.homepage {
                        LabeledContent("Homepage") {
                            Link(homepage.absoluteString, destination: homepage)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                Section {
                    if package.isOutdated {
                        Button {
                            Task { await store.perform(.upgrade(package)) }
                        } label: {
                            Label("Upgrade to \(package.latestVersion ?? "Latest")", systemImage: "arrow.up.circle")
                        }
                    }
                    if package.kind == .formula {
                        Button {
                            Task { await store.perform(package.isPinned ? .unpin(package) : .pin(package)) }
                        } label: {
                            Label(package.isPinned ? "Unpin" : "Pin at Current Version",
                                  systemImage: package.isPinned ? "pin.slash" : "pin")
                        }
                    }
                    Button(role: .destructive) {
                        confirmingUninstall = true
                    } label: {
                        Label("Uninstall…", systemImage: "trash")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog(
            "Uninstall \(package.displayName)?",
            isPresented: $confirmingUninstall
        ) {
            Button("Uninstall", role: .destructive) {
                Task { await store.perform(.uninstall(package)) }
            }
        } message: {
            Text("This runs `brew uninstall \(package.name)` and removes the files Homebrew manages for it.")
        }
    }

    private func header(for package: BrewPackage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: package.kind == .cask ? "macwindow" : "shippingbox.fill")
                .font(.system(size: 30))
                .foregroundStyle(package.kind == .cask ? .blue : .orange)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(package.displayName)
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(subtitle(for: package))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if package.isOutdated {
                Text("Update available")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding()
    }

    private func subtitle(for package: BrewPackage) -> String {
        var parts = [package.name, package.kind.label]
        if package.isInstalledAsDependency {
            parts.append("installed as dependency")
        }
        return parts.joined(separator: " · ")
    }
}

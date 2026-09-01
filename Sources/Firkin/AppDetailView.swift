import SwiftUI
import AppKit
import FirkinKit

/// Detail pane for an application found on disk.
struct AppDetailView: View {
    @Environment(PackageStore.self) private var store
    @State private var confirmingUninstall = false

    var body: some View {
        if let entry = store.detailAppEntry {
            detail(for: entry)
        } else {
            ContentUnavailableView(
                "No App Selected",
                systemImage: "square.grid.2x2",
                description: Text("Choose an application from the list to see its details.")
            )
        }
    }

    private func detail(for entry: PackageStore.AppEntry) -> some View {
        VStack(spacing: 0) {
            header(for: entry)
            Divider()
            Form {
                Section("Details") {
                    LabeledContent("Version", value: entry.app.version ?? "—")
                    LabeledContent("Architecture", value: architectureText(for: entry.app.architecture))
                    if let running = runningStatus(for: entry) {
                        LabeledContent("Running", value: running)
                    }
                    if let bundleID = entry.app.bundleID {
                        LabeledContent("Bundle ID", value: bundleID)
                    }
                    LabeledContent("Location") {
                        Text(entry.app.url.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Section("Homebrew") {
                    switch entry.management {
                    case let .managedByBrew(package):
                        LabeledContent("Cask", value: package.name)
                        LabeledContent("Installed", value: package.installedVersion ?? "—")
                        LabeledContent("Latest", value: package.normalizedLatestVersion ?? "—")
                        if package.autoUpdates {
                            LabeledContent("Updates", value: "App updates itself")
                        }
                        if package.isOutdated {
                            Button {
                                Task { await store.perform(.upgrade(package)) }
                            } label: {
                                Label("Upgrade to \(package.normalizedLatestVersion ?? "Latest")", systemImage: "arrow.up.circle")
                            }
                        }
                    case let .adoptable(package):
                        LabeledContent("Matching cask", value: package.name)
                        LabeledContent("App version", value: entry.app.version ?? "—")
                        LabeledContent("Homebrew has", value: package.normalizedLatestVersion ?? "—")
                        Button {
                            Task { await store.perform(.adopt(package)) }
                        } label: {
                            Label("Adopt into Homebrew", systemImage: "arrow.down.app")
                        }
                        .help("Runs brew install --cask --adopt so Homebrew manages this app's updates from now on")
                    case .unmanaged:
                        Text("No matching Homebrew cask was found for this app.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        confirmingUninstall = true
                    } label: {
                        Label(isBrewManaged(entry) ? "Uninstall…" : "Move to Trash…", systemImage: "trash")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog(
            isBrewManaged(entry) ? "Uninstall \(entry.app.name)?" : "Move \(entry.app.name) to the Trash?",
            isPresented: $confirmingUninstall
        ) {
            Button(isBrewManaged(entry) ? "Uninstall" : "Move to Trash", role: .destructive) {
                Task { await store.uninstallApp(entry) }
            }
        } message: {
            Text(uninstallMessage(for: entry))
        }
        .alert(
            "Could Not Move to Trash",
            isPresented: Binding(
                get: { store.appTrashError != nil },
                set: { if !$0 { store.appTrashError = nil } }
            )
        ) {
            Button("OK") { store.appTrashError = nil }
        } message: {
            Text("\(store.appTrashError ?? "") You can remove the app with Finder instead.")
        }
    }

    private func isBrewManaged(_ entry: PackageStore.AppEntry) -> Bool {
        if case .managedByBrew = entry.management { return true }
        return false
    }

    private func uninstallMessage(for entry: PackageStore.AppEntry) -> String {
        var message: String
        if case let .managedByBrew(package) = entry.management {
            message = "This runs `brew uninstall --cask \(package.name)` and removes the files Homebrew manages for it."
        } else {
            message = "Moves \(entry.app.bundleFileName) to the Trash. You can put it back from there."
        }
        if let bundleID = entry.app.bundleID,
           !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            message += " The app appears to be running right now."
        }
        return message
    }

    private func header(for entry: PackageStore.AppEntry) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: icon(for: entry))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.app.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(entry.app.bundleID ?? entry.app.url.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            ArchitectureChip(architecture: entry.app.architecture)
        }
        .padding()
    }

    private func icon(for entry: PackageStore.AppEntry) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: entry.app.url.path)
        image.size = NSSize(width: 44, height: 44)
        return image
    }

    private func architectureText(for architecture: AppArchitecture) -> String {
        switch architecture {
        case .appleSilicon: return "Apple Silicon (arm64)"
        case .universal: return "Universal (arm64 + x86_64)"
        case .intel:
            return architecture.requiresRosetta()
                ? "Intel (x86_64) — requires Rosetta 2"
                : "Intel (x86_64)"
        case .unknown: return "Unknown"
        }
    }

    /// Live check: if the app is running, report the architecture it is
    /// actually executing as — the definitive Rosetta answer.
    private func runningStatus(for entry: PackageStore.AppEntry) -> String? {
        guard let bundleID = entry.app.bundleID,
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return nil }
        switch running.executableArchitecture {
        case NSBundleExecutableArchitectureARM64:
            return "Yes — natively (arm64)"
        case NSBundleExecutableArchitectureX86_64:
            return ProcessInfo.isAppleSiliconMac
                ? "Yes — under Rosetta 2 (x86_64)"
                : "Yes — natively (x86_64)"
        default:
            return "Yes"
        }
    }
}
